extends CanvasLayer
## Readout and persistence for the injected player's camera settings.
const FILE := "user://gameplay_camera.cfg"
var actor: Node3D
var readout := Label.new()
var _previous: Dictionary = {}
var _dirty := false


func setup(player: Node3D) -> void:
	actor = player
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(readout)
	readout.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	readout.offset_left = -330
	readout.offset_right = -20
	readout.offset_top = 160
	readout.offset_bottom = 270
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_color_override("font_shadow_color", Color.BLACK)
	readout.add_theme_constant_override("shadow_offset_x", 2)
	readout.add_theme_constant_override("shadow_offset_y", 2)
	readout.hide()
	var config := ConfigFile.new()
	if config.load(FILE) == OK and config.get_value("camera_v1", "version", 0) == 1:
		var values: Variant = config.get_value("camera_v1", "view", {})
		if values is Dictionary:
			actor.call("set_camera_adjustment", values)
	_previous = actor.call("get_camera_adjustment")


func _process(_delta: float) -> void:
	if not is_instance_valid(actor):
		return
	var editing := not get_tree().paused and Input.is_key_pressed(KEY_ALT)
	readout.visible = editing
	if editing:
		var values: Dictionary = actor.call("get_camera_adjustment")
		if values != _previous:
			_previous = values
			_dirty = true
		var ru := TranslationServer.get_locale().begins_with("ru")
		readout.text = ("КАМЕРА · Alt + ЛКМ\nНаклон: %.2f°\nПоворот: %.2f°\nДистанция: %.2f м" if ru else "CAMERA · Alt + LMB\nPitch: %.2f°\nYaw: %.2f°\nDistance: %.2f m") % [_previous.pitch, _previous.yaw, _previous.distance]
	elif _dirty:
		_save()


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("camera_v1", "version", 1)
	config.set_value("camera_v1", "view", _previous)
	if config.save(FILE) == OK:
		_dirty = false
	else:
		push_warning("Camera settings could not be saved")


func _exit_tree() -> void:
	if _dirty:
		_save()
