extends RefCounted
## One lamp editor for both cases: the fields edit the live preview and the defaults of
## new placements, and while an installed lamp is selected the same fields edit that lamp.
var controls: Node
var _loading := false
# Palette defaults parked while an installed lamp occupies the fields.
var _parked: Dictionary = {}
var _color_edit_target: Node3D


func setup(owner_controls: Node) -> void:
	controls = owner_controls
	for spin: SpinBox in [controls.default_light_height, controls.default_light_energy, controls.default_light_angle, controls.default_flicker_step]:
		spin.value_changed.connect(_changed)
	controls.default_light_color.color_changed.connect(_color_changed)
	controls.default_light_color.popup_closed.connect(_color_popup_closed)
	controls.default_flicker_mode.item_selected.connect(_mode_changed)


func _changed(_value: float) -> void:
	apply()


func _color_changed(color: Color) -> void:
	if _loading:
		return
	if controls.objects.selected != null:
		apply_selected(color)
	else:
		apply_preview()


func _mode_changed(_index: int) -> void:
	apply()


func _color_popup_closed() -> void:
	_color_edit_target = null


func apply() -> void:
	if _loading:
		return
	if controls.objects.selected != null:
		apply_selected()
	else:
		apply_preview()


func apply_preview() -> void:
	var preview: Node3D = controls.objects.preview
	if preview == null or controls.objects._selected_kind() != "light":
		return
	controls._apply_special_default_height(preview, "light")
	controls._update_light_ui()


func is_lamp(node: Node3D) -> bool:
	return node != null and node.has_method("get_fixture_config") and node.has_method("set_authored_energy")


# Fills the fields from an installed lamp (null parks nothing and restores the palette defaults).
func load_from(lamp: Node3D) -> void:
	_loading = true
	if lamp == null:
		_restore_defaults()
	else:
		if _parked.is_empty():
			_park_defaults()
		controls.default_light_height.set_value_no_signal(lamp.global_position.y)
		controls.default_light_energy.set_value_no_signal(float(lamp.call("get_authored_energy")))
		controls.default_light_color.color = lamp.call("get_authored_color")
		var spot := lamp.find_child("Light", true, false) as SpotLight3D
		controls.default_light_angle.get_parent().visible = spot != null
		if spot != null:
			controls.default_light_angle.set_value_no_signal(spot.spot_angle)
		controls.default_flicker_mode.select(clampi(int(lamp.get_meta("planning_flicker_mode", 0)), 0, controls.default_flicker_mode.item_count - 1))
		controls.default_flicker_step.set_value_no_signal(float(lamp.get_meta("planning_flicker_step", 0.2)))
	_loading = false


func _park_defaults() -> void:
	_parked = {
		"height": controls.default_light_height.value, "energy": controls.default_light_energy.value,
		"angle": controls.default_light_angle.value, "color": controls.default_light_color.color,
		"mode": controls.default_flicker_mode.selected, "step": controls.default_flicker_step.value,
		"visible": controls.fixtures.default_visible.button_pressed,
	}


func _restore_defaults() -> void:
	if _parked.is_empty():
		return
	controls.default_light_height.set_value_no_signal(_parked["height"])
	controls.default_light_energy.set_value_no_signal(_parked["energy"])
	controls.default_light_angle.set_value_no_signal(_parked["angle"])
	controls.default_light_angle.get_parent().visible = true
	controls.default_light_color.color = _parked["color"]
	controls.default_flicker_mode.select(_parked["mode"])
	controls.default_flicker_step.set_value_no_signal(_parked["step"])
	controls.fixtures.default_visible.set_pressed_no_signal(_parked["visible"])
	_parked = {}


func apply_selected(picked: Variant = null) -> void:
	var lamp: Node3D = controls.objects.selected
	if not is_lamp(lamp):
		return
	var height: float = controls.default_light_height.value
	var energy: float = controls.default_light_energy.value
	var color: Color = controls.default_light_color.color if picked == null else picked
	var mode: int = controls.default_flicker_mode.get_selected_id()
	var step: float = controls.default_flicker_step.value
	var spot := lamp.find_child("Light", true, false) as SpotLight3D
	var angle: float = controls.default_light_angle.value
	var changed := not is_equal_approx(lamp.global_position.y, height) \
		or not is_equal_approx(float(lamp.call("get_authored_energy")), energy) \
		or not (lamp.call("get_authored_color") as Color).is_equal_approx(color) \
		or int(lamp.get_meta("planning_flicker_mode", 0)) != mode \
		or not is_equal_approx(float(lamp.get_meta("planning_flicker_step", 0.2)), step) \
		or (spot != null and not is_equal_approx(spot.spot_angle, angle))
	if not changed:
		return
	# One picker drag is one undo step; other fields record per edit.
	if picked == null or _color_edit_target != lamp:
		controls.session.edit_history.call("record_transform", lamp)
	_color_edit_target = lamp if picked != null else null
	lamp.global_position.y = height
	lamp.call("set_authored_energy", energy)
	lamp.call("set_authored_color", color)
	if spot != null:
		spot.spot_angle = angle
		lamp.set_meta("planning_light_angle", angle)
	if lamp.has_method("configure_flicker") and (int(lamp.get_meta("planning_flicker_mode", 0)) != mode or not is_equal_approx(float(lamp.get_meta("planning_flicker_step", 0.2)), step)):
		lamp.call("configure_flicker", mode, step)
	controls.session.geometry._clear_selection_highlight()
	controls.session.geometry._show_selection_highlight(lamp)
	controls._update_light_ui()
	controls.status.text = "СВЕТИЛЬНИК | высота %.2f м | яркость %.2f | конус %.0f°" % [height, energy, angle]
