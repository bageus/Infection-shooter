extends CanvasLayer
## Read-only runtime diagnostics; no infection or simulation state changes.
var infection: Node
var occlusion: Node
var label: Label
var _elapsed := 0.0


func setup(runtime: Node, effects: Node) -> void:
	infection = runtime
	occlusion = effects
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	label.position = Vector2(16, 110)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.hide()
	set_process(false)
	infection.control_loss_changed.connect(_control_loss_changed)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		label.visible = not label.visible
		set_process(label.visible)
		refresh()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= .25:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if not is_instance_valid(infection) or not is_instance_valid(occlusion):
		return
	label.text = "F3 DEBUG | FPS %d | render %.1f ms | physics %.1f ms\nMutation %.1f / threshold %.1f | control lost %s | paused %s\nOcclusion %d | walls %d | material variants %d | queued %d | rebuilds %d" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		infection.call("get_mutation"), infection.call("get_critical_threshold"), infection.call("is_control_lost"), get_tree().paused,
		occlusion.mode, occlusion.walls.records.size(), occlusion.walls.active_materials.size(), occlusion.walls.pending.size(), occlusion.rebuild_count]


func _control_loss_changed(active: bool) -> void:
	if active and label.visible:
		print("Runtime debug: mutation control loss, mutation=%.2f threshold=%.2f" % [infection.call("get_mutation"), infection.call("get_critical_threshold")])


func _exit_tree() -> void:
	if is_instance_valid(infection) and infection.control_loss_changed.is_connected(_control_loss_changed):
		infection.control_loss_changed.disconnect(_control_loss_changed)
