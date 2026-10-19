extends RefCounted
## Applies the four active mutation families; progression stays in infection.
const STRIKE_REACH := 3.0
const STRIKE_PUSH_SPEED := 6.0
# Same world, prop and enemy layers as the grenade blast.
const STRIKE_OBJECT_MASK := 7
const STRIKE_OBJECT_QUERY_LIMIT := 32

var host: Node
var running: Dictionary = {}
var _claw_visual := 0.0
var _dash_struck: Dictionary = {}


func _init(effects: Node) -> void:
	host = effects


func cast(id: String) -> void:
	var spec: Dictionary = host.runtime.call("skill_requirements", id)
	var level := int(spec.get("level", 1))
	if id.begins_with("blood_burst") or id == "blood_infection":
		_blood(id, level)
	elif id.begins_with("discharge"):
		_discharge(level)
	elif id.begins_with("power_strike"):
		_strike(level)
	elif id == "predator_dash":
		_dash_struck.clear()
		host.player.call("mutation_dash")
		host.vfx.dash_trail(0.4)
		_start(id, 0.4)
	elif id == "berserk":
		host._start_buff(id, 6.0)
	elif id == "storm_pulse":
		_start(id, 6.0)
		host.vfx.active_aura(id, 4.0, 6.0)
	elif id.begins_with("active_claws"):
		var duration: float = [2.5, 3.5, 4.5][level - 1]
		_start(id, duration)
		host.vfx.active_aura(id, float(level + 2), duration)


func _start(id: String, duration: float) -> void:
	running[id] = {"left": duration, "elapsed": 0.0}
	host._skill_effect(id, duration)


func tick(delta: float) -> void:
	_claw_visual -= delta
	for id: String in running.keys():
		var effect: Dictionary = running[id]
		var elapsed := minf(delta, float(effect.left))
		effect.left = maxf(0.0, float(effect.left) - delta)
		if id.begins_with("active_claws"):
			var level := int((host.runtime.call("skill_requirements", id) as Dictionary).get("level", 1))
			for enemy in host._enemies_near(host.player.global_position, float(level + 2)):
				if _claw_visual <= 0.0:
					host.vfx.claw_slash(enemy)
				enemy.call("take_damage", float(40 + level * 10) * elapsed)
		elif id == "storm_pulse":
			# Integrate damage continuously: exactly 40/s, independent of FPS.
			for enemy in host._enemies_near(host.player.global_position, 4.0):
				enemy.call("take_damage", 40.0 * elapsed)
				if float(effect.elapsed) <= 0.0:
					enemy.call("apply_blast_stun", 2.0, 1.0)
			effect.elapsed = float(effect.elapsed) - elapsed
			if float(effect.elapsed) <= 0.0:
				effect.elapsed += 1.0
		elif id == "predator_dash":
			_dash()
		if float(effect.left) <= 0.0:
			running.erase(id)
			host.vfx.buff_ended(id)
	if _claw_visual <= 0.0:
		_claw_visual = 0.2


func _blood(id: String, level: int) -> void:
	var infected := id == "blood_infection"
	var damage: float = 30.0 if infected else [20.0, 30.0, 50.0][level - 1]
	host.vfx.spike_burst(host.player.global_position, 2.4)
	for enemy in host._enemies_near(host.player.global_position, 2.4):
		var offset: Vector3 = enemy.global_position - host.player.global_position
		if level > 1:
			# Final distance is measured from the edge of the burst, not its centre.
			_push(enemy, offset, maxf(0.0, 2.4 - Vector2(offset.x, offset.z).length()) + (4.0 if level == 3 and not infected else 3.0))
		if level == 3 and not infected:
			enemy.call("apply_blast_stun", 1.0, 1.0)
		if infected:
			enemy.call("apply_skill_infection", 3.0, 10.0)
		enemy.call("take_damage", damage)
	if infected:
		host._skill_effect(id, 3.0)


func _discharge(level: int) -> void:
	var targets: Array = host._enemies_near(host.player.global_position, 8.0, true)
	if targets.is_empty():
		return
	var current: Node3D = targets[0]
	var points: Array[Vector3] = [host.player.global_position]
	for hit in [6, 8, 10][level - 1]:
		if not is_instance_valid(current) or float(current.get("health")) <= 0.0:
			break
		var origin := current.global_position
		points.append(origin)
		if level == 3:
			current.call("apply_blast_stun", 1.2, 1.0)
		current.call("take_damage", float(level * 10))
		var next: Node3D
		for candidate in host._enemies_near(origin, 3.0, true):
			if candidate != current:
				next = candidate
				break
		if next != null:
			current = next
	host.vfx.chain_lightning(points)


func _strike(level: int) -> void:
	var forward := -(host.player.get_node("AimPivot") as Node3D).global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	for enemy in host._enemies_near(host.player.global_position, 4.0):
		var offset: Vector3 = enemy.global_position - host.player.global_position
		var depth := offset.dot(forward)
		if depth < 0.0 or depth > 3.0 or absf(offset.dot(right)) > (1.0 + depth * 2.0 / 3.0) * 0.5:
			continue
		_push(enemy, forward, 4.0 if level == 1 else 5.0)
		if level == 3:
			enemy.call("apply_blast_stun", 1.5, 1.0)
		enemy.call("take_damage", float(20 + level * 10))
	_strike_objects(forward, float(20 + level * 10))
	host.vfx.power_strike(host.player.global_position, forward)


# Glass, partitions and furniture in front of the player: same reach as the
# blow. A box is used instead of the enemy cone, so it is slightly wider near
# the player.
func _strike_objects(forward: Vector3, damage: float) -> void:
	var player: CharacterBody3D = host.player
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.0, STRIKE_REACH)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis.looking_at(forward), player.global_position + forward * STRIKE_REACH * 0.5 + Vector3.UP * 0.9)
	query.collision_mask = STRIKE_OBJECT_MASK
	query.exclude = [player.get_rid()]
	var hit_ids := {}
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query, STRIKE_OBJECT_QUERY_LIMIT):
		var body := hit.get("collider") as Node3D
		if body == null or hit_ids.has(body.get_instance_id()) or not _strikeable(body):
			continue
		hit_ids[body.get_instance_id()] = true
		if body is RigidBody3D and not (body as RigidBody3D).freeze:
			body.call("push_from_character", player.global_position, forward * STRIKE_PUSH_SPEED, 1.0)
		body.call("take_melee_hit", damage, body.global_position, forward)


static func _strikeable(body: Node3D) -> bool:
	if body is CharacterBody3D or not body.has_method("take_melee_hit"):
		return false
	return not (body.is_in_group("infected") or body.is_in_group("player") or body.is_in_group("contactless_debris"))


func _dash() -> void:
	var forward: Vector3 = host.player.get("_roll_direction")
	var right := forward.cross(Vector3.UP).normalized()
	for enemy in host._enemies_near(host.player.global_position, 1.6):
		var id: int = enemy.get_instance_id()
		if _dash_struck.has(id):
			continue
		_dash_struck[id] = true
		var side: float = (enemy.global_position - host.player.global_position).dot(right)
		_push(enemy, right if side >= 0.0 else -right, 2.0)
		enemy.call("take_damage", 50.0)


func _push(enemy: Node3D, direction: Vector3, distance: float) -> void:
	if enemy.has_method("apply_skill_push"):
		enemy.call("apply_skill_push", direction, distance)


func cancel_unavailable() -> void:
	for id: String in running.keys():
		if not host.runtime.call("has_skill", id):
			running.erase(id)
			host.vfx.buff_ended(id)
