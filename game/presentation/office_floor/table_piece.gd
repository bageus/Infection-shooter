extends RigidBody3D

var table: Node3D
var piece_id: String
var last_stage := false
var _small_hits := 0


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
