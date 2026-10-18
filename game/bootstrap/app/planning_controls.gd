extends Node

const SURFACE_OPTIONS := preload("res://game/bootstrap/app/planning_surface_decal_options.gd")
const DECOR_POSES := preload("res://game/bootstrap/app/planning_decor_poses.gd")
const COLOR_POPUP := preload("res://game/bootstrap/app/planner_color_popup.gd")
const DISPLAY_OPTIONS := preload("res://game/bootstrap/app/planning_display_options.gd")
var display_options: Node
const LOOT_OPTIONS := preload("res://game/bootstrap/app/planning_loot_options.gd")
const DOOR_OPTIONS := preload("res://game/bootstrap/app/planning_door_options.gd")
var loot_options: Node
var door_options: Node
const SPAWN_OPTIONS := preload("res://game/bootstrap/app/planning_spawn_options.gd")
var spawn_options: Node
const FIXTURE_CONTROLS := preload("res://game/bootstrap/app/planning_light_fixtures.gd")
var fixtures = FIXTURE_CONTROLS.new()
var light_view = preload("res://game/bootstrap/app/planning_light_view.gd").new()
var fixture_toggles = preload("res://game/bootstrap/app/planning_fixture_toggles.gd").new()
var light_default_editor = preload("res://game/bootstrap/app/planning_light_defaults.gd").new()

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
var default_light_color: ColorPickerButton
var desk_setup_button: Button
var planning_toolbar: PanelContainer
var undo_button: Button
var duplicate_button: Button

var session: Variant
var objects: Variant
var catalog: Variant
var blood_options: HBoxContainer
var blood_surface: OptionButton
var blood_size: SpinBox


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
	default_light_color = session.ui.get_node("Panel/VBox/LightDefaults/ColorRow/Value")
	COLOR_POPUP.bind(default_light_color)
	default_flicker_mode.item_selected.connect(_on_default_flicker_mode_changed)
	desk_setup_button = Button.new()
	desk_setup_button.text = "Plan desk setup"
	desk_setup_button.visible = false
	session.ui.get_node("Panel/VBox").add_child(desk_setup_button)
	session.ui.get_node("Panel/VBox").move_child(desk_setup_button, palette.get_index() + 1)
	desk_setup_button.pressed.connect(_open_desk_setup)
	display_options = DISPLAY_OPTIONS.new()
	add_child(display_options)
	display_options.call("setup", session, objects)
	loot_options = LOOT_OPTIONS.new()
	add_child(loot_options)
	loot_options.call("setup", session, objects)
	door_options = DOOR_OPTIONS.new()
	add_child(door_options)
	door_options.call("setup", session, objects)
	spawn_options = SPAWN_OPTIONS.new()
	add_child(spawn_options)
	spawn_options.call("setup", session, objects)
	fixtures.setup(self)
	light_view.setup(self)
	fixture_toggles.setup(self)
	light_default_editor.setup(self)
	var box: Node = session.ui.get_node("Panel/VBox")
	for control_name in ["LightInfo", "LightLevel", "LightAngleInfo", "LightAngle"]:
		box.move_child(box.get_node(control_name), palette.get_index())
	_build_gore_controls()
	_build_planning_toolbar()
	var surface_options := SURFACE_OPTIONS.new()
	add_child(surface_options)
	surface_options.setup(session)


# Gore and Blood palettes (ADR-0017): dead infected, loose body parts and
# blood decals with a surface choice (floor/wall) and a size.
func _build_gore_controls() -> void:
	var tabs: Node = session.ui.get_node_or_null("Panel/VBox/Tabs")
	if tabs != null:
		for entry in [["Gore", _show_gore_catalog], ["Blood", _show_blood_catalog]]:
			var button := Button.new()
			button.name = str(entry[0])
			button.text = str(entry[0])
			button.pressed.connect(entry[1])
			tabs.add_child(button)
	var weapons := Button.new()
	weapons.name = "Weapons"
	weapons.text = "Weapons"
	weapons.pressed.connect(_show_weapon_catalog)
	var items := Button.new()
	items.name = "Items"
	items.text = "Items"
	items.tooltip_text = "Key, DNA, ammo, medkits, antidote"
	items.pressed.connect(_show_item_catalog)
	var palette_box: Node = session.ui.get_node("Panel/VBox")
	palette_box.add_child(items)
	palette_box.move_child(items, palette.get_index())
	palette_box.add_child(weapons)
	palette_box.move_child(weapons, palette.get_index())
	blood_options = HBoxContainer.new()
	blood_options.name = "BloodOptions"
	var surface_label := Label.new()
	surface_label.text = "Surface"
	blood_options.add_child(surface_label)
	blood_surface = OptionButton.new()
	blood_surface.add_item("Пол")
	blood_surface.add_item("Стена")
	blood_surface.add_item("Объект")
	blood_surface.item_selected.connect(_blood_surface_changed)
	blood_options.add_child(blood_surface)
	var size_label := Label.new()
	size_label.text = "Size"
	blood_options.add_child(size_label)
	blood_size = SpinBox.new()
	blood_size.min_value = 0.2
	blood_size.max_value = 5.0
	blood_size.step = 0.1
	blood_size.value = 1.0
	blood_size.value_changed.connect(func(_value: float) -> void: objects._rebuild_preview())
	blood_options.add_child(blood_size)
	blood_options.hide()
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(blood_options)
	box.move_child(blood_options, palette.get_index())


func _show_gore_catalog() -> void:
	_enter_simple_catalog(catalog.gore_catalog, "GORE | dead infected and body parts")


func _show_blood_catalog() -> void:
	_enter_simple_catalog(catalog.blood_catalog(), "BLOOD | choose surface and size, then place")
	blood_options.show()


func _enter_simple_catalog(entries: Array, title: String) -> void:
	light_defaults.hide()
	blood_options.hide()
	objects._reset_selection()
	session.ui.get_node("Panel/VBox/GroupTabs").hide()
	catalog.active_catalog = entries
	light_defaults.hide()
	_rebuild_palette()
	status.text = title


# Applies palette options to a freshly created object before it enters the tree.
func _configure_new_asset(node: Node3D, entry: Dictionary) -> void:
	DECOR_POSES.configure_new(node, objects.preview)
	display_options.call("configure_new", node)
	loot_options.call("configure_new", node)
	spawn_options.call("configure_new", node)
	fixtures.configure_new_asset(node, entry)
	if str(entry.get("kind", "")) != "blood" or not node.has_method("configure_blood"):
		return
	var surface: String = ["floor", "wall", "object"][blood_surface.selected] if blood_surface != null else "floor"
	node.call("configure_blood", str(entry.get("blood_texture", "splatter_01")), surface)
	var size := float(blood_size.value) if blood_size != null else 1.0
	node.scale = Vector3.ONE * size


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


## Which settings panel edits this object ("" when it has none): the same panel serves the
## palette preview and an installed object, so a click on an installed one can open it.
func settings_kind(node: Node3D) -> String:
	if node == null:
		return ""
	if light_default_editor.is_lamp(node):
		return "lamp"
	if door_options.lockable_controller(node) != null:
		return "door"
	if display_options.applies_to(node):
		return "display"
	if node.has_method("configure_spawn"):
		return "spawn"
	if node.has_method("configure_stats"):
		return "enemy"
	if loot_options.applies_to(node):
		return "loot"
	return ""


func _update_light_ui() -> void:
	if display_options != null:
		display_options.call("update")
	if loot_options != null:
		loot_options.call("update")
	if door_options != null:
		door_options.call("update")
	if spawn_options != null:
		spawn_options.call("update")
	var target = objects.selected
	if target == null and objects.preview != null and objects._selected_kind() == "light":
		target = objects.preview
	var light: Light3D
	if target != null:
		light = target.find_child("Light", true, false) as Light3D
	var show_light = light != null and target.has_method("get_authored_energy")
	var lamp_selected: bool = light_default_editor.is_lamp(objects.selected)
	light_defaults.visible = lamp_selected or (objects.selected == null and objects._selected_kind() == "light")
	if light_defaults.visible:
		light_defaults.get_node("Title").text = _lamp_title(objects.selected) if lamp_selected else str(objects.selected_entry.get("name", "Светильник"))
	light_default_editor.load_from(objects.selected if lamp_selected else null)
	fixtures.update_selection(objects.selected)
	light_info.visible = show_light
	light_level.visible = show_light
	light_angle_info.visible = show_light and light is SpotLight3D
	light_angle.visible = show_light and light is SpotLight3D
	if show_light:
		light_info.text = "LIGHT %.2f / 16.00" % float(target.call("get_authored_energy"))
		light_level.value = float(target.call("get_authored_energy"))
		if light is SpotLight3D:
			var spot = light as SpotLight3D
			light_angle_info.text = "CONE %.0f°" % spot.spot_angle
			light_angle.value = spot.spot_angle


func _lamp_title(lamp: Node3D) -> String:
	var shape: int = fixtures.SHAPES.find(str(lamp.call("get_fixture_config")["shape"]))
	return "Светильник: " + fixtures.LABELS[maxi(shape, 0)]


func _on_default_flicker_mode_changed(_index: int) -> void:
	default_flicker_step.value = _recommended_flicker_step(default_flicker_mode.get_selected_id())


func _recommended_flicker_step(mode: int) -> float:
	match mode:
		1: return 0.12
		2: return 0.75
		3: return 1.5
	return 0.2


func _rebuild_palette() -> void:
	light_view.update_catalog()
	palette.clear()
	for entry: Dictionary in catalog.active_catalog:
		palette.add_item(str(entry.get("name", "")))
	if spawn_options != null:
		spawn_options.call("update")


func _show_structure_catalog() -> void:
	if blood_options != null:
		blood_options.hide()
	light_defaults.hide()
	objects._reset_selection()
	catalog.active_catalog = catalog.group_catalogs["01"]
	light_defaults.hide()
	session.ui.get_node("Panel/VBox/GroupTabs").show()
	_rebuild_palette()
	status.text = "STRUCTURE | choose building object"


func _show_structure_group(group_name: String) -> void:
	light_defaults.hide()
	objects._reset_selection()
	catalog.active_catalog = catalog.group_catalogs.get(group_name, [])
	light_defaults.hide()
	_rebuild_palette()
	status.text = "STRUCTURE " + group_name


func _show_lighting_catalog() -> void:
	if blood_options != null:
		blood_options.hide()
	objects._reset_selection()
	light_defaults.show()
	session.ui.get_node("Panel/VBox/GroupTabs").hide()
	catalog.active_catalog = catalog.lighting_catalog
	_rebuild_palette()
	status.text = "LIGHTING | lights and darkness zones"
	_update_light_ui()


func _show_weapon_catalog() -> void:
	if blood_options != null:
		blood_options.hide()
	light_defaults.hide()
	objects._reset_selection()
	session.ui.get_node("Panel/VBox/GroupTabs").hide()
	catalog.active_catalog = catalog.weapon_catalog
	_rebuild_palette()
	status.text = "WEAPONS | place weapon pickups"


func _show_item_catalog() -> void:
	if blood_options != null:
		blood_options.hide()
	light_defaults.hide()
	objects._reset_selection()
	session.ui.get_node("Panel/VBox/GroupTabs").hide()
	catalog.active_catalog = catalog.item_catalog
	_rebuild_palette()
	status.text = "ITEMS | key, DNA, ammo, medkits, antidote"


func _show_actor_catalog() -> void:
	if blood_options != null:
		blood_options.hide()
	light_defaults.hide()
	objects._reset_selection()
	session.ui.get_node("Panel/VBox/GroupTabs").hide()
	catalog.active_catalog = catalog.actor_catalog
	light_defaults.hide()
	_rebuild_palette()
	status.text = "ACTORS | place/remove Player and Infected"


func _apply_special_default_height(node: Node3D, kind: String) -> void:
	if kind == "light":
		node.global_position.y = float(default_light_height.value) if default_light_height != null else LIGHT_DEFAULT_HEIGHT
		_apply_new_light_defaults(node)
	elif kind == "darkness" or kind == "exploration_darkness":
		node.global_position.y = DARKNESS_DEFAULT_HEIGHT
	elif kind == "spawn_point":
		node.global_position.y = 0.0


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


func _blood_surface_changed(_index: int) -> void:
	objects._rebuild_preview()
	status.text = "КРОВЬ | выберите место: " + ["пол", "стена", "поверхность объекта"][blood_surface.selected]
