extends RefCounted
## Palette fields edit the live lamp preview and defaults for new placements.
var controls: Node


func setup(owner_controls: Node) -> void:
	controls = owner_controls
	for spin: SpinBox in [controls.default_light_height, controls.default_light_energy, controls.default_light_angle, controls.default_flicker_step]:
		spin.value_changed.connect(_changed)
	controls.default_light_color.color_changed.connect(_color_changed)
	controls.default_flicker_mode.item_selected.connect(_mode_changed)


func _changed(_value: float) -> void:
	apply_preview()


func _color_changed(_color: Color) -> void:
	apply_preview()


func _mode_changed(_index: int) -> void:
	apply_preview()


func apply_preview() -> void:
	var preview: Node3D = controls.objects.preview
	if preview == null or controls.objects._selected_kind() != "light":
		return
	controls._apply_special_default_height(preview, "light")
	controls._update_light_ui()
