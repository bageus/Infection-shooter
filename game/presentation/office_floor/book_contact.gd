extends RefCounted

# Books remain physical and shootable, while their collision layer does not
# block characters. A nearby player tips a standing book and nudges it away.
static func kick_if_close(book: RigidBody3D, cooldown: float, delta: float) -> float:
	cooldown = maxf(0.0, cooldown - delta)
	if cooldown > 0.0:
		return cooldown
	var player := book.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return 0.0
	var offset := book.global_position - player.global_position
	if absf(offset.y) > 1.15 or Vector2(offset.x, offset.z).length_squared() > 0.65:
		return 0.0
	var away := Vector3(offset.x, 0.0, offset.z)
	if away.length_squared() < 0.001:
		away = -player.global_basis.z
		away.y = 0.0
	away = away.normalized()
	book.sleeping = false
	book.apply_central_impulse((away + Vector3.UP * 0.22) * clampf(book.mass * 0.9, 0.12, 0.75))
	book.apply_torque_impulse(Vector3.UP.cross(away) * clampf(book.mass * 1.5, 0.2, 0.9))
	return 0.55
