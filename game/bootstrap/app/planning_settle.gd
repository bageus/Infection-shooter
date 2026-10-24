extends RefCounted
## Simulate the complete movable scene before publishing prepared transforms.
const PROBE := preload("res://game/bootstrap/app/planning_physics_probe.gd")
const MAX_TICKS := 3600
const MAX_MSEC := 120000
const QUIET_TICKS := 12
var tick_limit := MAX_TICKS
var time_limit_msec := MAX_MSEC
var ticks := 0
var elapsed_msec := 0
var contact_guards := 0
var failure_reason := ""
var _bodies: Array[RigidBody3D] = []
var _corpses: Array[Node3D] = []


func run(session: Node, nodes: Array, status: Label) -> bool:
	var tree := session.get_tree()
	if not tree.paused: return false
	var started := Time.get_ticks_msec()
	var dirty := false
	for index in nodes.size():
		var node: Variant = nodes[index]
		if not is_instance_valid(node) or not node is Node3D: continue
		dirty = dirty or not node.has_meta("planning_settled_transform") or node.get_meta("planning_settled_transform") != node.transform or int(node.get_meta("planning_settled_count", -1)) != nodes.size()
		if node.has_method("prepare_planner_physics"):
			_corpses.append(node)
			dirty = dirty or not (node.call("get_decor_pose") as Dictionary).has("physics_v1")
		_collect_bodies(node, _bodies)
		if index % 16 == 15:
			status.text = "CHECKING PHYSICS | %d / %d" % [index + 1, nodes.size()]
			await tree.process_frame
			if not _alive(session): return false
	if not dirty:
		print("Planner physics: unchanged prepared layer")
		return true
	_invalidate(nodes)
	var bones: Array = []
	# All props and decorative articulated bodies share one simulation. A prop
	# cannot settle on a frozen neighbour that will be moved in a later batch.
	for corpse: Variant in _corpses:
		if not is_instance_valid(corpse): continue
		corpse.call("prepare_planner_physics")
		bones.append_array(corpse.find_children("*", "PhysicalBone3D", true, false))
		await tree.process_frame
		if not _alive(session):
			_finalize_corpses()
			return false
	for body: Variant in _bodies:
		if not is_instance_valid(body): continue
		PROBE.lift_embedded(body)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = false
		body.sleeping = false
	status.text = "SETTLING ENTIRE LOCATION | %d props, %d bodies" % [_bodies.size(), _corpses.size()]
	var success := await _step(session, bones, status)
	_finalize_corpses()
	await _sleep_bodies(tree)
	if not _alive(session): return false
	if success:
		for node: Variant in nodes:
			if is_instance_valid(node):
				node.set_meta("planning_settled_transform", node.transform)
				node.set_meta("planning_settled_count", nodes.size())
	elapsed_msec = Time.get_ticks_msec() - started
	print("Planner whole-world physics: %d props, %d bodies, %d ticks, %d ms, complete=%s" % [_bodies.size(), _corpses.size(), ticks, elapsed_msec, success])
	return success


func _step(session: Node, bones: Array, status: Label) -> bool:
	var tree := session.get_tree()
	var previous := {}
	var quiet := 0
	var started := Time.get_ticks_msec()
	var frame := Engine.get_physics_frames()
	var corpses_done := bones.is_empty()
	var energy_quiet := {}
	var message := status.text
	PhysicsServer3D.set_active(true)
	while ticks < tick_limit and Time.get_ticks_msec() - started < time_limit_msec:
		await tree.process_frame
		if not _alive(session):
			PhysicsServer3D.set_active(not tree.paused)
			return false
		var current_frame := Engine.get_physics_frames()
		var advanced := current_frame - frame
		if advanced <= 0: continue
		frame = current_frame
		ticks += advanced
		_stabilize_supported(advanced, energy_quiet)

		quiet = mini(quiet + advanced, QUIET_TICKS) if _quiet(_bodies, previous) else 0
		status.text = "%s | stable %d / %d | %.1fs" % [message, quiet, QUIET_TICKS, ticks / float(Engine.physics_ticks_per_second)]
		if not corpses_done and quiet >= QUIET_TICKS and ticks >= 180 and PROBE.supported(bones):
			# Supported articulated joints may keep rotating. Freeze their settled
			# pose only after the furniture underneath has stopped, then verify the
			# entire rigid scene again against the final corpse colliders.
			_finalize_corpses()
			corpses_done = true
			quiet = 0
			previous.clear()
			contact_guards += 1
		if corpses_done and quiet >= QUIET_TICKS and ticks >= 30:
			PhysicsServer3D.set_active(not tree.paused)
			return true
	PhysicsServer3D.set_active(not tree.paused)
	failure_reason = "Physics did not settle; previous save unchanged. Check moving/red objects and retry"
	return false


func _finalize_corpses() -> void:
	for corpse: Variant in _corpses:
		if is_instance_valid(corpse): corpse.call("finalize_planner_physics")


func _sleep_bodies(tree: SceneTree) -> void:
	for index in _bodies.size():
		var body: Variant = _bodies[index]
		if is_instance_valid(body):
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.sleeping = true
			PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, true)
		if index % 16 == 15: await tree.process_frame


static func _invalidate(nodes: Array) -> void:
	for node: Variant in nodes:
		if not is_instance_valid(node): continue
		for key in ["planning_settled_transform", "planning_settled_count"]:
			if node.has_meta(key): node.remove_meta(key)


static func _alive(session: Node) -> bool:
	return is_instance_valid(session) and session.is_inside_tree()


static func _collect_bodies(node: Node, result: Array[RigidBody3D]) -> void:
	if node is RigidBody3D and not node.freeze: result.append(node)
	for child in node.get_children(): _collect_bodies(child, result)


static func _quiet(samples: Array, previous: Dictionary) -> bool:
	var quiet := true
	for sample: Variant in samples:
		if not is_instance_valid(sample): continue
		var rid: RID = sample.get_rid()
		# During a paused-tree server step the native sleep state is the source
		# of truth; transform synchronization can still deliver the last pose.
		if bool(PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING)):
			previous[sample] = sample.global_transform
			continue
		var before: Transform3D = previous.get(sample, sample.global_transform)
		var moved := before.origin.distance_squared_to(sample.global_position)
		var turned := before.basis.orthonormalized().get_rotation_quaternion().normalized().angle_to(sample.global_basis.orthonormalized().get_rotation_quaternion().normalized())
		var linear: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var angular: Vector3 = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		quiet = quiet and linear.length_squared() < 0.01 and angular.length_squared() < 0.02 and moved < 0.000025 and turned < 0.01
		previous[sample] = sample.global_transform
	return quiet


## Jolt can apply endless penetration recovery to a supported body with zero
## kinetic energy. Permit sleep only after two seconds of low energy and an
## upward contact with immovable geometry; falling/moving supports never pass.
func _stabilize_supported(advanced: int, counters: Dictionary) -> void:
	for body: Variant in _bodies:
		if not is_instance_valid(body): continue
		if bool(PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING)): continue
		var id: int = body.get_instance_id()
		var linear: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var angular: Vector3 = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		if linear.length_squared() >= 0.0001 or angular.length_squared() >= 0.0001:
			counters[id] = 0
			continue
		counters[id] = int(counters.get(id, 0)) + advanced
		if int(counters[id]) < 120: continue
		var params := PhysicsTestMotionParameters3D.new()
		params.from = body.global_transform
		params.motion = Vector3.DOWN * 0.04
		params.margin = 0.001
		params.recovery_as_collision = true
		params.max_collisions = 32
		var result := PhysicsTestMotionResult3D.new()
		var hit := PhysicsServer3D.body_test_motion(body.get_rid(), params, result)

		if not hit: continue
		for index in result.get_collision_count():
			var support := result.get_collider(index)
			if result.get_collision_normal(index).y > 0.7 and (support is StaticBody3D or (support is RigidBody3D and support.freeze)):
				body.sleeping = true
				PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, true)
				contact_guards += 1
				break
