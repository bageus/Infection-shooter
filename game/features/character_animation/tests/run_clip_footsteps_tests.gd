extends SceneTree
const STEPS := preload("res://game/features/character_animation/clip_footsteps.gd")
var failures := 0


func _init() -> void:
	_check(STEPS.step_side("Walk", 0.5, 0.6) == 0 and STEPS.step_side("Walk", 0.9, 0.1) == 1, "walk cycle lands the left foot, then the right across the loop")
	_check(STEPS.step_side("Run", 0.1, 0.3) == 0 and STEPS.step_side("Run", 0.7, 0.8) == 1, "run cycle steps are paced differently")
	_check(STEPS.step_side("Walk", 0.2, 0.3) == -1 and STEPS.step_side("Idle", 0.0, 1.0) == -1, "no step between contacts and none for idle")
	print("Clip footstep tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
