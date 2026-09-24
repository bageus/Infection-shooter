extends RigidBody3D

var table: Node3D


func take_projectile_hit_at_shape(
	_damage: float, hit_position: Vector3, _normal: Vector3,
	direction: Vector3, _weapon: String, shape_index: int
) -> bool:
	if not is_instance_valid(table):
		return true
	if shape_index < 0:
		table.call("hit_piece", "Top", hit_position, direction)
		return true
	var owner_id := shape_find_owner(shape_index)
	var shape_node := shape_owner_get_owner(owner_id) as CollisionShape3D
	if shape_node != null:
		table.call("hit_piece", shape_node.name, hit_position, direction)
	return true


func take_projectile_hit(_damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, _weapon: String) -> bool:
	if is_instance_valid(table):
		table.call("hit_piece", "Top", hit_position, direction)
	return true
