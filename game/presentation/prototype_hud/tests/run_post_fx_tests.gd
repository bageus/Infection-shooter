extends SceneTree

const FX := preload("res://game/presentation/prototype_hud/post_fx.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(FX.hit_for_loss(0.0, 100.0) == 0.0 and FX.hit_for_loss(-5.0, 100.0) == 0.0, "No hit without a loss")
	_check(FX.hit_for_loss(1.0, 100.0) >= FX.HIT_MIN, "A small hit still reads")
	_check(FX.hit_for_loss(50.0, 100.0) == 1.0, "A big hit saturates")
	var fx: CanvasLayer = FX.new()
	root.add_child(fx)
	await process_frame
	fx.update(0.016, 100.0, 100.0)
	_check(fx.get_node("Base").visible and not fx.get_node("Hit").visible, "Base grade is on, hit pass is off at rest")
	fx.update(0.016, 80.0, 100.0)
	_check(fx.get_node("Hit").visible and fx.hit > 0.5, "Losing health starts the hit flash")
	for i in 20:
		fx.update(0.05, 80.0, 100.0)
	_check(not fx.get_node("Hit").visible and fx.hit == 0.0, "The hit flash fades out")
	fx.update(0.016, 100.0, 100.0)
	_check(fx.hit == 0.0, "Healing does not flash")
	fx.update(0.016, 70.0, 100.0)
	fx.set_enabled(false)
	_check(not fx.get_node("Base").visible and not fx.get_node("Hit").visible and fx.hit == 0.0, "Disabled setting hides everything")
	fx.set_enabled(true)
	_check(fx.get_node("Base").visible, "Re-enabling restores the grade")
	fx.free()
	print("post_fx tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
