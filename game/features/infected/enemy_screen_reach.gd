extends RefCounted
## Decides whether an enemy could reach the camera frame within about a second,
## so enemies beyond it can skip animation work.


# Centre and four points one second of travel (plus a margin) away.
static func could_be_seen(enemy: Node3D, move_speed: float) -> bool:
	var camera := enemy.get_viewport().get_camera_3d()
	if camera == null:
		return true
	var reach := move_speed + 1.5
	var p := enemy.global_position + Vector3.UP
	for offset in [Vector3.ZERO, Vector3(reach, 0, 0), Vector3(-reach, 0, 0), Vector3(0, 0, reach), Vector3(0, 0, -reach)]:
		if camera.is_position_in_frustum(p + offset):
			return true
	return false


# Animation runs only for enemies that can reach the frame within about a
# second; the check runs every 6th frame.
static func update(enemy: Node3D, animation: Node, asleep: bool) -> void:
	if animation == null or Engine.get_physics_frames() % 6 != enemy.get_instance_id() % 6:
		return
	# F6 bisect switch: level 1 and up bring back the old behaviour (animation always runs).
	var wanted := not asleep and not bool(Engine.get_meta("probe_no_animation", false)) and (int(Engine.get_meta("legacy_perf", 0)) >= 1 or could_be_seen(enemy, float(enemy.get("move_speed"))))
	if wanted != bool(animation.call("is_active")):
		animation.call("set_active", wanted)
	animation.get("step_state").set_step(animation.get("animation_player"), _step_for(enemy))


# Skeleton poses every frame within 12 m of the player, every 2nd frame to 22 m, every 4th beyond.
static func _step_for(enemy: Node3D) -> int:
	var player := enemy.get_tree().get_first_node_in_group("player") as Node3D
	if player == null or int(Engine.get_meta("legacy_perf", 0)) >= 1:
		return 1
	var ground := Vector2(enemy.global_position.x - player.global_position.x, enemy.global_position.z - player.global_position.z).length()
	return 1 if ground < 12.0 else (2 if ground < 22.0 else 4)
