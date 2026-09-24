extends RigidBody3D

var table: Node3D
var piece_id: String
var last_stage := false


func take_projectile_hit(_damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, _weapon: String) -> bool:
	if last_stage:
		sleeping = false
		apply_impulse(direction.normalized() * 0.9, hit_position - global_position)
	else:
		table.call("hit_piece", piece_id, hit_position, direction)
	return true


func take_melee_hit(_damage: float, hit_position: Vector3, direction: Vector3) -> void:
	take_projectile_hit(0.0, hit_position, Vector3.ZERO, direction, "MELEE")
