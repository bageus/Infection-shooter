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
	var wanted := not asleep and could_be_seen(enemy, float(enemy.get("move_speed")))
	if wanted != bool(animation.call("is_active")):
		animation.call("set_active", wanted)
