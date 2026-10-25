extends SceneTree
## Control-loss filter: shows a countdown digit that grows and fades, fades out slowly
## after control returns, then hides so it costs nothing.

const OVERLAY := preload("res://game/presentation/prototype_hud/control_loss_overlay.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var overlay := OVERLAY.new()
	root.add_child(overlay)
	var digit := overlay.get_child(0) as Label
	_expect(not overlay.visible, "The filter starts hidden.")
	_expect(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The filter never blocks mouse input.")
	overlay.call("update", 0.5, 4.9)
	_expect(overlay.visible and digit.visible and digit.text == "5", "The countdown shows the whole seconds left.")
	var early_scale := digit.scale.x
	overlay.call("update", 0.0, 4.2)
	_expect(digit.text == "5" and digit.scale.x > early_scale, "A digit grows while its second runs.")
	overlay.call("update", 0.0, 4.0)
	_expect(digit.modulate.a < 0.05, "A digit has faded out when its second ends.")
	overlay.call("update", 0.0, 3.5)
	_expect(digit.text == "4" and digit.modulate.a > 0.1, "The next digit takes its place.")
	for frame in range(60):
		overlay.call("update", 1.0 / 60.0, 1.0)
	_expect(is_equal_approx((overlay.material as ShaderMaterial).get_shader_parameter("strength"), 1.0), "The filter reaches full strength.")
	overlay.call("update", 0.5, 0.0)
	_expect(overlay.visible and not digit.visible, "After control returns the filter lingers without the countdown.")
	for frame in range(180):
		overlay.call("update", 1.0 / 60.0, 0.0)
	_expect(not overlay.visible, "The filter fades out gradually and then hides.")
	print("Control loss overlay tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
