extends SceneTree
const STATE := preload("res://game/presentation/prototype_hud/vital_bar_feedback_state.gd")
const VIEW := preload("res://game/presentation/prototype_hud/vital_bar_feedback.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_count_and_retarget()
	_test_trail_and_pulse()
	_test_continuous_and_range()
	await _test_view()
	await process_frame
	print("Vital bar feedback tests: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _test_count_and_retarget() -> void:
	for values in [Vector2(100, 85), Vector2(10, 25), Vector2(80, 0)]:
		var state := STATE.new()
		state.set_value(values.x, 100)
		_check(state.displayed == roundi(values.x) and not state.active(), "Initial values snap without false feedback")
		state.set_value(values.y, 100)
		var previous: int = state.displayed
		for frame in 140:
			state.advance(0.02)
			_check(absi(state.displayed - previous) <= 1, "Numbers count by single integers")
			previous = state.displayed
		_check(state.displayed == roundi(values.y), "Counter reaches health/mutation target including zero")
	var state := STATE.new()
	state.set_value(100, 100)
	state.set_value(20, 100)
	state.advance(0.02)
	state.set_value(98, 100)
	state.advance(0.02)
	_check(state.displayed == 98, "Healing retargets the visible count without playing an obsolete damage queue")
	for i in 100:
		state.set_value(20 if i % 2 == 0 else 80, 100)
		state.advance(0.016)
	state.set_value(79, 100)
	for i in 100:
		state.advance(0.02)
	_check(state.displayed == 79 and not state.active(), "Rapid alternating changes settle on the latest value")


func _test_trail_and_pulse() -> void:
	for direction in [-1, 1]:
		var state := STATE.new()
		state.set_value(50, 100)
		state.set_value(50 + direction * 20, 100)
		_check(state.trail == 50 and state.white_alpha == 1, "Changed interval initially stays white")
		state.advance(0.1)
		_check(state.trail == 50 and state.white_alpha == 1, "White interval has a short hold")
		state.advance(0.04)
		_check(is_equal_approx(state.pulse_scale, 1.0 + direction * 0.05), "Pulse peaks at exactly 95 or 105 percent")
		for i in 80:
			state.advance(0.02)
			_check(state.pulse_scale >= 0.95 - 0.00001 and state.pulse_scale <= 1.05 + 0.00001, "Pulse never stacks beyond five percent")
		_check(state.white_alpha == 0 and state.trail == state.target and state.pulse_scale == 1, "White fades and scale returns exactly to baseline")
	var reverse := STATE.new()
	reverse.set_value(100, 100)
	reverse.set_value(60, 100)
	reverse.set_value(80, 100)
	_check(reverse.trail == 60 and reverse.target == 80, "Direction reversal highlights the newly gained interval")


func _test_continuous_and_range() -> void:
	var state := STATE.new()
	state.set_value(0, 100)
	for frame in 300:
		state.set_value(frame * 0.1, 100)
		state.advance(1.0 / 60)
	_check(state.target - state.trail < 1, "Continuous mutation has a bounded trailing band instead of an ever-growing white fill")
	state.set_value(75, 150)
	_check(state.displayed == 75 and state.white_alpha == 0 and state.pulse_scale == 1, "Changing maximum health re-syncs without phantom damage")
	state.set_value(999, 150)
	_check(state.target == 150, "Values are clamped to the actual range")
	state.set_value(-10, 150)
	_check(state.target == 0, "Negative values cannot draw outside the bar")


func _test_view() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(420, 100)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var panel := Control.new()
	viewport.add_child(panel)
	var bar := ProgressBar.new()
	bar.position = Vector2(20, 40)
	bar.size = Vector2(300, 14)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.RED
	bar.add_theme_stylebox_override("fill", fill)
	bar.modulate = Color(0.2, 1, 0.2)
	panel.add_child(bar)
	var label := Label.new()
	panel.add_child(label)
	var marker := ColorRect.new()
	marker.size = Vector2(2, 20)
	panel.add_child(marker)
	var view := VIEW.new()
	view.configure(bar, label, marker)
	view.set_marker_fraction(0.7)
	view.set_value(100, 100)
	view.advance(0)
	view.set_value(60, 100)
	view.advance(0)
	_check(view.get_parent() == bar.get_parent() and view.get_index() < marker.get_index(), "White overlay is a sibling, below the critical marker and outside bar tint")
	_check(bar.value == 60 and label.text == "100 / 100", "Fill changes immediately while the numeric label counts")
	_check(view.flash_rect().position.x >= 0 and view.flash_rect().end.x <= bar.size.x, "White interval stays inside bar bounds")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot := viewport.get_texture().get_image()
		var white := screenshot.get_pixel(275, 47)
		_check(white.r > 0.95 and white.g > 0.95 and white.b > 0.95, "Actual white trail pixels remain white under a tinted health/mutation bar")
	else:
		print("White pixel assertion deferred to rendered Compatibility/Forward+ CI")
	view.advance(0.14, Vector2(1, 1.6))
	_check(bar.scale.is_equal_approx(Vector2(0.95, 1.52)), "Pulse composes with the existing control-loss bar height")
	var centre := bar.position + bar.size * 0.5
	_check(is_equal_approx(marker.position.x + marker.size.x * 0.5, centre.x + bar.size.x * 0.2 * bar.scale.x), "Critical marker follows the pulsed bar's actual threshold position")
	bar.self_modulate.a = 0.2
	view.advance(0)
	_check(is_equal_approx(float(view.get("_blink_alpha")), 0.2), "DNA ampule blink is preserved on the white trail")
	bar.size.x = 350
	await process_frame
	view.advance(0)
	_check(view.size.x == 350, "Resizing updates the trail geometry")
	viewport.queue_free()
	await process_frame
