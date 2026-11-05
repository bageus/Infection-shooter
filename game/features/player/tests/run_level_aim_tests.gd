extends SceneTree

const PLAYER_SCRIPT := preload("res://game/features/player/player_aim_level.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var origin := Vector3(0, 9, 0)
	var down := Vector3(0, -0.6, -0.8).normalized()
	# Wall face above gun height (1.2): aim moves to where the cursor ray crosses gun height.
	var high_hit := origin + down * 6.0
	var leveled := PLAYER_SCRIPT.level_aim_point(high_hit, origin, down, 1.2)
	_check(is_equal_approx(leveled.y, 1.2), "Aim above gun height is clamped to gun height")
	_check((leveled - origin).normalized().dot(down) > 0.9999, "Clamped aim stays on the cursor ray")
	# Floor hit below gun height keeps the exact hit point.
	var low_hit := Vector3(0, 0, -3)
	_check(PLAYER_SCRIPT.level_aim_point(low_hit, origin, down, 1.2) == low_hit, "Hit below gun height is unchanged")
	# Hit at gun height is unchanged.
	var level_hit := Vector3(0, 1.2, -4)
	_check(PLAYER_SCRIPT.level_aim_point(level_hit, origin, down, 1.2) == level_hit, "Hit at gun height is unchanged")
	# Camera below gun height looking up: the plane crossing is behind the camera, so keep the hit.
	var up_hit := Vector3(0, 4, -2)
	_check(PLAYER_SCRIPT.level_aim_point(up_hit, Vector3.ZERO, Vector3.DOWN, 1.2) == up_hit, "Plane behind the camera keeps the hit")
	print("Level aim tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", message)
