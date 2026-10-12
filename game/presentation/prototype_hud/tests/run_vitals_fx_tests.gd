extends SceneTree

const FX := preload("res://game/presentation/prototype_hud/vitals_screen_fx.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(FX.smoke_target(0.0, 30.0, false) == 0.0, "No smoke with an empty mutagen bar")
	_check(FX.smoke_target(10.0, 30.0, false) == 0.0, "No smoke far from the threshold")
	var near := FX.smoke_target(24.0, 30.0, false)
	_check(near > 0.3 and near < 1.0, "Smoke grows near the threshold")
	_check(FX.smoke_target(29.0, 30.0, false) > near, "Smoke keeps growing with the bar")
	_check(FX.smoke_target(10.0, 30.0, true) == 1.0, "Full smoke while control is lost")
	_check(FX.blood_target(100.0, 100.0) == 0.0 and FX.blood_target(70.0, 100.0) == 0.0, "No blood at healthy values")
	_check(FX.blood_target(40.0, 100.0) > 0.0 and FX.blood_target(40.0, 100.0) < 1.0, "Blood appears gradually")
	_check(FX.blood_target(10.0, 100.0) == 1.0, "Full blood at very low health")
	_check(FX.breathing_target(80.0, 100.0) == 0.0 and FX.breathing_target(20.0, 100.0) > 0.5, "Breathing only at low health")

	var fx: Control = FX.new()
	root.add_child(fx)
	await process_frame
	fx.update(0.1, 0.0, 30.0, false, 100.0, 100.0)
	_check(not fx.get_child(0).visible, "Overlay is hidden when both meters are fine")
	for i in 120:
		fx.update(0.1, 29.0, 30.0, false, 10.0, 100.0)
	_check(fx.get_child(0).visible and fx.smoke > 0.9 and fx.blood > 0.9, "Overlay reaches full strength")
	_check((fx.get("_breathing") as AudioStreamPlayer).playing and (fx.get("_pressure") as AudioStreamPlayer).playing, "Loops play at critical values")
	var before: float = fx.blood
	fx.update(0.1, 0.0, 30.0, false, 100.0, 100.0)
	_check(fx.blood < before and fx.blood > 0.0, "Effects fade out smoothly on recovery")
	for i in 120:
		fx.update(0.1, 0.0, 30.0, false, 100.0, 100.0)
	_check(not fx.get_child(0).visible and not (fx.get("_breathing") as AudioStreamPlayer).playing, "Everything stops after recovery")
	fx.free()
	await process_frame
	print("vitals fx tests: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
