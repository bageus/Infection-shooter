extends Node

const LIGHT_DEFAULT_HEIGHT = 2.5
const DARKNESS_DEFAULT_HEIGHT = 2.75

var palette: ItemList
var status: Label
var help: Label
var help_button: Button
var light_info: Label
var light_level: ProgressBar
var light_angle_info: Label
var light_angle: ProgressBar
var light_defaults: VBoxContainer
var default_light_height: SpinBox
var default_light_energy: SpinBox
var default_light_angle: SpinBox
var default_flicker_mode: OptionButton
var default_flicker_step: SpinBox
var selected_flicker_mode: OptionButton
var selected_flicker_step: SpinBox
var editing_flicker = false
var default_light_color: ColorPickerButton
var selected_light_color: ColorPickerButton
var _color_edit_target: Node3D
var desk_setup_button: Button
var planning_toolbar: PanelContainer
var undo_button: Button
var duplicate_button: Button

var session: Variant
var objects: Variant
var catalog: Variant


func configure(context: Dictionary) -> void:
	session = context["session"]
	objects = context["objects"]
	catalog = context["catalog"]


func setup_controls() -> void:
	palette = session.ui.get_node("Panel/VBox/Palette")
	status = session.ui.get_node("Panel/VBox/Status")
	help = session.ui.get_node("HelpPanel/VBox/Help")
	help_button = Button.new()
	help_button.text = "?"
	help_button.tooltip_text = "Planning controls"
	help_button.custom_minimum_size = Vector2(36, 36)
	session.ui.add_child(help_button)
	help_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help_button.position = Vector2(-52, 8)
	help_button.pressed.connect(_toggle_help)
	session.ui.get_node("HelpPanel/VBox/Close").pressed.connect(_toggle_help)
	light_info = session.ui.get_node("Panel/VBox/LightInfo")
	light_level = session.ui.get_node("Panel/VBox/LightLevel")
	light_angle_info = session.ui.get_node("Panel/VBox/LightAngleInfo")
	light_angle = session.ui.get_node("Panel/VBox/LightAngle")
	light_defaults = session.ui.get_node("Panel/VBox/LightDefaults")
	default_light_height = session.ui.get_node("Panel/VBox/LightDefaults/HeightRow/Value")
	default_light_energy = session.ui.get_node("Panel/VBox/LightDefaults/EnergyRow/Value")
	default_light_angle = session.ui.get_node("Panel/VBox/LightDefaults/AngleRow/Value")
	default_flicker_mode = session.ui.get_node("Panel/VBox/LightDefaults/FlickerRow/Mode")
	default_flicker_step = session.ui.get_node("Panel/VBox/LightDefaults/FlickerStepRow/Value")
	selected_flicker_mode = session.ui.get_node("Panel/VBox/SelectedFlicker/Mode")
	selected_flicker_step = session.ui.get_node("Panel/VBox/SelectedFlickerStep/Value")
	default_light_color = session.ui.get_node("Panel/VBox/LightDefaults/ColorRow/Value")
	selected_light_color = session.ui.get_node("Panel/VBox/SelectedLightColor/Value")
	selected_light_color.color_changed.connect(_on_selected_color_changed)
	selected_light_color.popup_closed.connect(_on_color_popup_closed)
	default_flicker_mode.item_selected.connect(_on_default_flicker_mode_changed)
	selected_flicker_mode.item_selected.connect(_on_selected_flicker_changed)
	selected_flicker_step.value_changed.connect(_on_selected_flicker_step_changed)
	desk_setup_button = Button.new()
	desk_setup_button.text = "Plan desk setup"
	desk_setup_button.visible = false
	session.ui.get_node("Panel/VBox").add_child(desk_setup_button)
	session.ui.get_node("Panel/VBox").move_child(desk_setup_button, palette.get_index() + 1)
	desk_setup_button.pressed.connect(_open_desk_setup)
	_build_planning_toolbar()


func _build_planning_toolbar() -> void:
	planning_toolbar = PanelContainer.new()
	planning_toolbar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	planning_toolbar.offset_left = -165
	planning_toolbar.offset_right = 165
	planning_toolbar.offset_top = 8
	planning_toolbar.offset_bottom = 48
	planning_toolbar.mouse_filter = Control.MOUSE_FILTER_STOP
	var toolbar_style = StyleBoxFlat.new()
	toolbar_style.bg_color = Color(0.005, 0.035, 0.065, 0.95)
	toolbar_style.border_color = Color(0.02, 0.72, 0.98)
	toolbar_style.set_border_width_all(2)
	toolbar_style.set_corner_radius_all(8)
	toolbar_style.corner_detail = 1
	toolbar_style.anti_aliasing = false
	planning_toolbar.add_theme_stylebox_override("panel", toolbar_style)
	session.ui.add_child(planning_toolbar)
	var toolbar_buttons = HBoxContainer.new()
	planning_toolbar.add_child(toolbar_buttons)
	var button_theme := Theme.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var inherited := planning_toolbar.get_theme_stylebox(state, "Button")
		if inherited is StyleBoxFlat:
			var style := inherited.duplicate() as StyleBoxFlat
			style.corner_detail = 1
			style.anti_aliasing = false
			button_theme.set_stylebox(state, "Button", style)
	toolbar_buttons.theme = button_theme
	undo_button = Button.new()
	undo_button.text = "Undo last action"
	undo_button.pressed.connect(func() -> void: session.edit_history.call("undo"))
	toolbar_buttons.add_child(undo_button)
	duplicate_button = Button.new()
	duplicate_button.text = "Duplicate selected"
	duplicate_button.pressed.connect(func() -> void: session.edit_history.call("duplicate_selected"))
	toolbar_buttons.add_child(duplicate_button)
	_update_history_buttons()


func _update_history_buttons() -> void:
	if undo_button != null:
		undo_button.disabled = (session.edit_history.get("stack") as Array).is_empty()
	if duplicate_button != null:
		duplicate_button.disabled = objects.selected == null or objects.selected == session.main_player


func _open_desk_setup() -> void:
	if objects.selected != null and desk_setup_button.visible:
		session.desk_setup.open(objects.selected)


func _toggle_help() -> void:
	var overlay = help.get_parent().get_parent() as Control
	overlay.visible = not overlay.visible


func _update_light_ui() -> void:
	var target = objects.selected
	if target == null and objects.preview != null and objects._selected_kind() == "light":
		target = objects.preview
	var light: Light3D
	if target != null:
		light = target.find_child("Light", true, false) as Light3D
	var show_light = light != null and target.has_method("get_authored_energy")
	session.ui.get_node("Panel/VBox/SelectedLightColor").visible = show_light and objects.selected != null
	light_info.visible = show_light
	light_level.visible = show_light
	light_angle_info.visible = show_light and light is SpotLight3D
	light_angle.visible = show_light and light is SpotLight3D
	session.ui.get_node("Panel/VBox/SelectedFlicker").visible = show_light and objects.selected != null
	session.ui.get_node("Panel/VBox/SelectedFlickerStep").visible = show_light and objects.selected != null
	if show_light:
		light_info.text = "LIGHT %.2f / 16.00" % float(target.call("get_authored_energy"))
		light_level.value = float(target.call("get_authored_energy"))
		if light is SpotLight3D:
			var spot = light as SpotLight3D
			light_angle_info.text = "CONE %.0f°" % spot.spot_angle
			light_angle.value = spot.spot_angle
		if objects.selected != null:
			selected_light_color.color = target.call("get_authored_color")
			editing_flicker = true
			selected_flicker_mode.select(int(target.get_meta("planning_flicker_mode", 0)))
			selected_flicker_step.value = float(target.get_meta("planning_flicker_step", 0.2))
			editing_flicker = false


func _on_selected_color_changed(color: Color) -> void:
	var target: Node3D = objects.selected
	if target == null or not target.has_method("set_authored_color"):
		return
	if (target.call("get_authored_color") as Color).is_equal_approx(color):
		return
	# One picker gesture is one undo action, including continuous dragging.
	if _color_edit_target != target:
		session.edit_history.call("record_transform", target)
		_color_edit_target = target
	target.call("set_authored_color", color)
	status.text = "LIGHT | оттенок #" + color.to_html(false)


func _on_color_popup_closed() -> void:
	_color_edit_target = null


func _on_selected_flicker_changed(_index: int) -> void:
	if not editing_flicker:
		selected_flicker_step.value = _recommended_flicker_step(selected_flicker_mode.get_selected_id())
	_apply_selected_flicker()


func _on_default_flicker_mode_changed(_index: int) -> void:
	default_flicker_step.value = _recommended_flicker_step(default_flicker_mode.get_selected_id())


func _recommended_flicker_step(mode: int) -> float:
	match mode:
		1: return 0.12
		2: return 0.75
		3: return 1.5
	return 0.2


func _on_selected_flicker_step_changed(_value: float) -> void:
	_apply_selected_flicker()


func _apply_selected_flicker() -> void:
	if editing_flicker or objects.selected == null or not objects.selected.has_method("configure_flicker"):
		return
	objects.selected.call("configure_flicker", selected_flicker_mode.get_selected_id(), selected_flicker_step.value)


func _rebuild_palette() -> void:
	palette.clear()
	for entry: Dictionary in catalog.active_catalog:
		palette.add_item(str(entry.get("name", "")))


func _show_structure_catalog() -> void:
	light_defaults.hide()
	objects._reset_selection()
	catalog.active_catalog = catalog.group_catalogs["01"]
	session.ui.get_node("Panel/VBox/GroupTabs").show()
	_rebuild_palette()
	status.text = "STRUCTURE | choose building object"


func _show_structure_group(group_name: String) -> void:
	light_defaults.hide()
	objects._reset_selection()
	catalog.active_catalog = catalog.group_catalogs.get(group_name, [])
	_rebuild_palette()
	status.text = "STRUCTURE " + group_name


func _show_lighting_catalog() -> void:
	objects._reset_selection()
	light_defaults.show()
	session.ui.get_node("Panel/VBox/GroupTabs").hide()
	catalog.active_catalog = catalog.lighting_catalog
	_rebuild_palette()
	status.text = "LIGHTING | lights and darkness zones"


func _show_actor_catalog() -> void:
	light_defaults.hide()
	objects._reset_selection()
	session.ui.get_node("Panel/VBox/GroupTabs").hide()
	catalog.active_catalog = catalog.actor_catalog
	_rebuild_palette()
	status.text = "ACTORS | place/remove Player and Infected"


func _apply_special_default_height(node: Node3D, kind: String) -> void:
	if kind == "light":
		node.global_position.y = float(default_light_height.value) if default_light_height != null else LIGHT_DEFAULT_HEIGHT
		_apply_new_light_defaults(node)
	elif kind == "darkness" or kind == "exploration_darkness":
		node.global_position.y = DARKNESS_DEFAULT_HEIGHT


func _apply_new_light_defaults(node: Node3D) -> void:
	var spot = node.find_child("Light", true, false) as SpotLight3D
	if spot == null:
		return
	var energy = float(default_light_energy.value) if default_light_energy != null else 3.0
	var angle = float(default_light_angle.value) if default_light_angle != null else 48.0
	node.call("set_authored_energy", energy)
	node.call("set_authored_color", default_light_color.color)
	spot.spot_angle = angle
	node.set_meta("planning_light_angle", angle)
	if node.has_method("configure_flicker"):
		node.call("configure_flicker", default_flicker_mode.get_selected_id(), default_flicker_step.value)


func _adjust_selected_light(amount: float) -> void:
	if objects.selected == null:
		return
	var light = objects.selected.find_child("Light", true, false) as Light3D
	if light == null:
		return
	session.edit_history.call("record_transform", objects.selected)
	objects.selected.call("set_authored_energy", clampf(float(objects.selected.call("get_authored_energy")) + amount, 0.0, 16.0))
	_update_light_ui()
	status.text = "LIGHT | brightness %.2f | [ / ] adjust" % float(objects.selected.call("get_authored_energy"))


func _adjust_selected_light_angle(amount: float) -> void:
	if objects.selected == null:
		return
	var light = objects.selected.find_child("Light", true, false) as SpotLight3D
	if light == null:
		return
	session.edit_history.call("record_transform", objects.selected)
	light.spot_angle = clampf(light.spot_angle + amount, 5.0, 89.0)
	objects.selected.set_meta("planning_light_angle", light.spot_angle)
	_update_light_ui()
	status.text = "LIGHT | cone %.0f° | , / . adjust" % light.spot_angle
