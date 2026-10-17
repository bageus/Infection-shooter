extends RefCounted
## Six-metre dash, stops at scenery while its damage window remains active.
var active := false
var remaining := 0.0
var _mask := 0
var _before := Vector3.ZERO


func begin(player: CharacterBody3D) -> void:
	if active:
		return
	active = true
	remaining = 6.0
	_mask = player.collision_mask
	player.collision_mask &= ~2
	player._roll_direction = -player.aim_pivot.global_basis.z
	player._roll_direction.y = 0.0
	player._roll_direction = player._roll_direction.normalized()
	player._roll_remaining = 0.4
	player._roll_pace = 15.0


func before_move(player: CharacterBody3D, delta: float) -> void:
	_before = player.global_position
	if active:
		player._roll_pace = minf(player._roll_pace, remaining / maxf(delta, 0.0001))


func after_move(player: CharacterBody3D) -> void:
	if not active:
		return
	remaining = maxf(0.0, remaining - Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(_before.x, _before.z)))
	for index in player.get_slide_collision_count():
		if player.get_slide_collision(index).get_normal().dot(player._roll_direction) < -0.1:
			player._roll_pace = 0.0
	if player._roll_remaining <= 0.0:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		player.collision_mask = _mask
		active = false
