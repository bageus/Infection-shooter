extends RefCounted
## Settle contacting groups while gameplay stays paused; keep incomplete saves private.
const PROBE := preload("res://game/bootstrap/app/planning_physics_probe.gd")
const BATCH_SIZE := 192
const MAX_TICKS := 720
const MAX_MSEC := 15000
const QUIET_TICKS := 12
var tick_limit := MAX_TICKS
var time_limit_msec := MAX_MSEC
var ticks := 0
var elapsed_msec := 0
var contact_guards := 0
var _bodies: Array[RigidBody3D] = []
var _corpses: Array[Node3D] = []
var _authored: Dictionary = {}


func run(session: Node, nodes: Array, status: Label) -> bool:
	var tree := session.get_tree()
	if not tree.paused:
		return false
	var started := Time.get_ticks_msec()
	var pending: Array[RigidBody3D] = []
	var dirty := false
	for index in nodes.size():
		var candidate: Variant = nodes[index]
		if not is_instance_valid(candidate) or not candidate is Node3D:
			continue
		var node: Node3D = candidate
		dirty = dirty or not node.has_meta("planning_settled_transform") or node.get_meta("planning_settled_transform") != node.transform or int(node.get_meta("planning_settled_count", -1)) != nodes.size()
		if node.has_method("prepare_planner_physics"):
			_corpses.append(node)
			dirty = dirty or not (node.call("get_decor_pose") as Dictionary).has("physics_v1")
		_collect_bodies(node, _bodies)
		if index % 16 == 15:
			status.text = "CHECKING PHYSICS | %d / %d" % [index + 1, nodes.size()]
			await tree.process_frame
			if not _alive(session):
				return false
	if not dirty:
		print("Planner physics: unchanged prepared layer")
		return true
	for index in _bodies.size():
		var body: Variant = _bodies[index]
		_authored[body] = body.transform
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		if PROBE.may_move(body):
			if body.has_method("get_decor_pose"):
				PROBE.lift_embedded(body)
			pending.append(body)
		body.freeze = true
		if index % 16 == 15:
			await tree.process_frame
			if not _alive(session):
				await _restore_bodies(tree)
				return false
	var groups := await _groups(session, pending, status)
	if not _alive(session):
		await _restore_bodies(tree)
		return false
	var success := true
	for index in groups.size():
		var batch: Array = groups[index]
		for body: RigidBody3D in batch:
			body.freeze = false
			body.sleeping = false
		status.text = "SETTLING PROPS | %d / %d batches" % [index + 1, groups.size()]
		if not await _step(session, batch, status):
			success = false
			break
		for body: RigidBody3D in batch:
			body.freeze = true
	if success:
		success = await _settle_corpses(session, status)
	if not success:
		_restore_authored(nodes)
	await _restore_bodies(tree)
	if not _alive(session):
		return false
	if success:
		for node: Variant in nodes:
			if is_instance_valid(node):
				node.set_meta("planning_settled_transform", node.transform)
				node.set_meta("planning_settled_count", nodes.size())
	elapsed_msec = Time.get_ticks_msec() - started
	print("Planner physics: %d pending props / %d, %d bodies, %d ticks, %d ms, %d contact guards, complete=%s" % [pending.size(), _bodies.size(), _corpses.size(), ticks, elapsed_msec, contact_guards, success])
	return success


func _settle_corpses(session: Node, status: Label) -> bool:
	for offset in range(0, _corpses.size(), 4):
		var samples: Array = []
		var batch: Array = _corpses.slice(offset, offset + 4)
		for corpse: Node3D in batch:
			corpse.call("prepare_planner_physics")
			samples.append_array(corpse.find_children("*", "PhysicalBone3D", true, false))
			await session.get_tree().process_frame
			if not _alive(session):
				return false
		status.text = "SETTLING BODIES | %d / %d" % [offset, _corpses.size()]
		var success := await _step(session, samples, status)
		for corpse: Node3D in batch:
			if is_instance_valid(corpse):
				corpse.call("finalize_planner_physics")
		if not success:
			return false
	return true


func _step(session: Node, samples: Array, status: Label) -> bool:
	var tree := session.get_tree()
	var previous := {}
	var quiet := 0
	var started := Time.get_ticks_msec()
	var frame := Engine.get_physics_frames()
	var step_ticks := 0
	var message := status.text
	PhysicsServer3D.set_active(true)
	while step_ticks < tick_limit and Time.get_ticks_msec() - started < time_limit_msec:
		await tree.process_frame
		if not _alive(session):
			PhysicsServer3D.set_active(not tree.paused)
			return false
		var current_frame := Engine.get_physics_frames()
		var advanced := current_frame - frame
		if advanced <= 0:
			continue
		frame = current_frame
		step_ticks += advanced
		ticks += advanced
		quiet = mini(quiet + advanced, QUIET_TICKS) if _quiet(samples, previous) else 0
		status.text = "%s | stable %d / %d" % [message, quiet, QUIET_TICKS]
		if quiet >= QUIET_TICKS and step_ticks >= 30 and PROBE.supported(samples):
			break
		# Jolt may alternate penetration recovery with zero kinetic energy.
		if step_ticks >= 120 and PROBE.resting(samples) and PROBE.supported(samples):
			contact_guards += 1
			quiet = QUIET_TICKS
			break
		# At rest without upward support (wedged against a wall or prop): nothing
		# moves any more, and waiting for support that cannot come never ends.
		if quiet >= QUIET_TICKS and step_ticks >= 120:
			break
		# As with retained gameplay ragdolls, supported articulated bodies have a
		# finite settling window: joints can keep rotating without translational energy.
		if step_ticks >= 180 and PROBE.articulated(samples) and PROBE.supported(samples):
			contact_guards += 1
			quiet = QUIET_TICKS
			break
	PhysicsServer3D.set_active(not tree.paused)
	return quiet >= QUIET_TICKS


## A timed-out preparation must not lose authored positions (or bless them as settled).
func _restore_authored(nodes: Array) -> void:
	for body: Variant in _authored:
		if is_instance_valid(body):
			body.transform = _authored[body]
	for node: Variant in nodes:
		if is_instance_valid(node):
			if node.has_meta("planning_settled_transform"):
				node.remove_meta("planning_settled_transform")
			if node.has_meta("planning_settled_count"):
				node.remove_meta("planning_settled_count")


func _restore_bodies(tree: SceneTree) -> void:
	for index in _bodies.size():
		var body: Variant = _bodies[index]
		if is_instance_valid(body):
			body.freeze = false
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.sleeping = true
		if index % 16 == 15:
			await tree.process_frame


func _groups(session: Node, pending: Array[RigidBody3D], status: Label) -> Array[Array]:
	var lookup := {}
	for body in _bodies:
		lookup[body.get_rid()] = body
	var visited := {}
	var groups: Array[Array] = []
	var batch: Array = []
	var biggest := 0
	var started := Time.get_ticks_msec()
	for candidate in pending:
		if visited.has(candidate):
			continue
		var component: Array[RigidBody3D] = [candidate]
		visited[candidate] = true
		var cursor := 0
		while cursor < component.size():
			var body := component[cursor]
			cursor += 1
			for neighbor: RigidBody3D in _neighbors(body, lookup):
				if not visited.has(neighbor):
					visited[neighbor] = true
					component.append(neighbor)
			if cursor % 16 == 0:
				await session.get_tree().process_frame
				if not _alive(session):
					return []
		biggest = maxi(biggest, component.size())
		if batch.size() + component.size() > BATCH_SIZE and not batch.is_empty():
			groups.append(batch)
			batch = []
		batch.append_array(component)
		if visited.size() % 16 == 0 or Time.get_ticks_msec() - started >= 4:
			status.text = "GROUPING PHYSICS | %d / %d" % [visited.size(), _bodies.size()]
			await session.get_tree().process_frame
			if not _alive(session):
				return []
			started = Time.get_ticks_msec()
	if not batch.is_empty():
		groups.append(batch)
	print("Planner physics groups: %d batches, largest connected group %d" % [groups.size(), biggest])
	return groups


static func _neighbors(body: RigidBody3D, lookup: Dictionary) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	var space := body.get_world_3d().direct_space_state
	for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
		if shape.disabled or shape.get_parent() != body or shape.shape == null:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.margin = 0.02
		query.collision_mask = body.collision_mask
		query.exclude = [body.get_rid()]
		for hit: Dictionary in space.intersect_shape(query, 128):
			if lookup.has(hit.rid) and not result.has(lookup[hit.rid]):
				result.append(lookup[hit.rid])
	return result


static func _alive(session: Node) -> bool:
	return is_instance_valid(session) and session.is_inside_tree()


static func _collect_bodies(node: Node, result: Array[RigidBody3D]) -> void:
	if node is RigidBody3D and not node.freeze:
		result.append(node)
	for child in node.get_children():
		_collect_bodies(child, result)


static func _quiet(samples: Array, previous: Dictionary) -> bool:
	var quiet := true
	for sample: Variant in samples:
		if not is_instance_valid(sample):
			continue
		if sample is RigidBody3D:
			# Rigid props rest by their velocities. Jolt's penetration recovery can
			# nudge a wedged prop a few centimetres in one tick, which is not motion.
			quiet = quiet and (sample.sleeping or (sample.linear_velocity.length_squared() < 0.01 and sample.angular_velocity.length_squared() < 0.02))
			previous[sample] = sample.global_transform
			continue
		var before: Transform3D = previous.get(sample, sample.global_transform)
		var moved := before.origin.distance_squared_to(sample.global_position)
		var turned := before.basis.orthonormalized().get_rotation_quaternion().normalized().angle_to(sample.global_basis.orthonormalized().get_rotation_quaternion().normalized())
		quiet = quiet and moved < 0.000025 and turned < 0.01
		previous[sample] = sample.global_transform
	return quiet
