extends RigidBody3D

var table: Node3D
var piece_id: String
var last_stage := false
var _small_hits := 0
var _kick_cooldown := 0.0


func _physics_process(delta: float) -> void:
	_kick_cooldown -= delta
	if not bool(get_meta("kickable", false)) or _kick_cooldown > 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var offset := global_position - player.global_position
	if absf(offset.y) > 1.4 or Vector2(offset.x, offset.z).length_squared() > 0.7:
		return
	_kick_cooldown = 0.8
	var away := Vector3(offset.x, 0.0, offset.z).normalized()
	sleeping = false
	apply_central_impulse((away + Vector3.UP * 0.25) * 0.6)


func take_projectile_hit(_damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, _weapon: String) -> bool:
	if last_stage:
		_small_hits += 1
		if _small_hits >= 3:
			queue_free()
			return true
		sleeping = false
		apply_impulse(direction.normalized() * 0.9, hit_position - global_position)
	elif is_instance_valid(table):
		table.call("hit_piece", piece_id, hit_position, direction)
	return true


func take_melee_hit(_damage: float, hit_position: Vector3, direction: Vector3) -> void:
	take_projectile_hit(0.0, hit_position, Vector3.ZERO, direction, "MELEE")
