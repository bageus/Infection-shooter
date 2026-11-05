extends SceneTree
## The defeat menu must wait for the death fade: not before DURATION, once after.
const FADE := preload("res://game/bootstrap/app/death_fade.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fade := FADE.new()
	root.add_child(fade)
	var shown := [0]
	fade.finished.connect(func() -> void: shown[0] += 1)
	var failures := 0
	fade._process(FADE.DURATION * 0.5)
	if shown[0] != 0:
		failures += 1
		push_error("Defeat menu shown before the fade ended")
	fade._process(FADE.DURATION)
	fade._process(1.0)
	if shown[0] != 1:
		failures += 1
		push_error("Defeat menu must show exactly once, got %d" % shown[0])
	if FADE.DURATION < 2.0 or FADE.DURATION > 5.0:
		failures += 1
		push_error("Fade outside the requested 2-5 seconds")
	print("Death fade tests: %d failures" % failures)
	quit(failures)
