extends Node

const SAVE_PATH := "user://planned_layout.json"
const MAPS_DIR := "user://maps"
const AUTHORED_SCENE_PATH := "res://game/presentation/office_floor/public/base_office_layout.tscn"
const GRID_SIZE := 0.25
const SNAP_DISTANCE := 0.8
const FLOOR_WALL_SNAP := preload("res://game/bootstrap/app/floor_wall_snap.gd")
const EXTINGUISHER_WALL := preload("res://game/bootstrap/app/extinguisher_wall_placement.gd")
const CAMERA_SPEED := 18.0
const CAMERA_ZOOM_STEP := 2.5
const CAMERA_MIN_HEIGHT := -15.0
const CAMERA_MAX_HEIGHT := 55.0
const SCALE_STEP := 0.1
const HEIGHT_STEP := 0.25
const LIGHT_DEFAULT_HEIGHT := HEIGHT_STEP * 10.0
const DARKNESS_DEFAULT_HEIGHT := HEIGHT_STEP * 11.0
const CAMERA_ROTATE_SPEED := 0.008
const PLAN_HALF_WIDTH := 40.0
const PLAN_HALF_DEPTH := 30.0

var host: Node3D
var camera: Camera3D
var root: Node3D
var structure_root: Node3D
var gameplay_root: Node3D
var enemies_root: Node3D
var main_player: Node3D
var player_spawn_defined := false
var player_spawn_transform := Transform3D.IDENTITY
var ui: Control
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
var editing_flicker := false
var hud_nodes: Array[Node] = []
var active := false
var selected_path := ""
var selected_kind := ""
var preview: Node3D
var selected: Node3D
var rotation_y := 0.0
var last_mouse_world := Vector3.ZERO
var placed: Array[Node3D] = []
var camera_anchor := Vector3.ZERO
var camera_height := 24.0
var saved_camera_transform := Transform3D.IDENTITY
var saved_camera_rig_transform := Transform3D.IDENTITY
var camera_rig: Node3D
var camera_yaw := 0.0
var camera_pitch := -0.75
var planning_yaw := 0.0
var planning_pitch := -0.75
var selection_box: MeshInstance3D
var selection_source_aabb := AABB()
var planning_grid: MeshInstance3D
var active_catalog: Array = []
var map_name_edit: LineEdit
var map_select: OptionButton

const ENVIRONMENT_ROOT := "res://models/objects/enviroments"
const ENVIRONMENT_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BATHROOM_FIXTURE_SCENE := preload("res://game/presentation/office_floor/public/props/bathroom_fixture.tscn")
const PAPER_PROP_SCENE := preload("res://game/presentation/office_floor/public/props/paper_prop.tscn")
const STAIRCASE_SCENE := preload("res://game/presentation/office_floor/public/structural/staircase.tscn")
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const DESK_SETUP_MODE := preload("res://game/bootstrap/app/desk_setup_mode.gd")
const EDIT_HISTORY := preload("res://game/bootstrap/app/planning_edit_history.gd")

var workstation_transforms: Dictionary = {}
var desk_setup: Node
var desk_setup_button: Button
var edit_history: RefCounted
var planning_toolbar: PanelContainer
var undo_button: Button
var duplicate_button: Button
var _drag_recorded := false

var group_catalogs: Dictionary = {}


var lighting_catalog := [
	{"name":"Omni Light","path":"res://game/presentation/office_floor/public/props/planner_light.tscn","kind":"light"},
	{"name":"Permanent Darkness","path":"res://game/presentation/office_floor/public/props/darkness_zone.tscn","kind":"darkness"},
	{"name":"Exploration Darkness","path":"res://game/presentation/office_floor/public/props/darkness_zone.tscn","kind":"exploration_darkness"}
]

var actor_catalog := [
	{"name":"Player Spawn","path":"","kind":"player"},
	{"name":"Zombie L1","path":"res://game/features/infected/public/infected_capsule.tscn","kind":"enemy"},
	{"name":"Mutant L2","path":"res://game/features/infected/public/mutant_level2.tscn","kind":"enemy"}
]


const PLANNING_CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const PLANNING_VIEW := preload("res://game/bootstrap/app/planning_view.gd")
const PLANNING_OBJECTS := preload("res://game/bootstrap/app/planning_objects.gd")
const PLANNING_GEOMETRY := preload("res://game/bootstrap/app/planning_geometry.gd")
const PLANNING_STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")

var catalog = PLANNING_CATALOG.new(self)
var view = PLANNING_VIEW.new(self)
var objects = PLANNING_OBJECTS.new(self)
var geometry = PLANNING_GEOMETRY.new(self)
var storage = PLANNING_STORAGE.new(self)


func setup(app_owner: Node3D, planning_root: Node3D, planning_ui: Control) -> void:
	host = app_owner
	root = planning_root
	structure_root = host.get_node("Structure")
	gameplay_root = host.get_node("Gameplay")
	enemies_root = host.get_node("Gameplay/Enemies")
	main_player = host.get_node("Gameplay/Player")
	ui = planning_ui
	camera_rig = host.get_node("Gameplay/Player/CameraRig") as Node3D
	camera = host.get_node("Gameplay/Player/CameraRig/Camera3D")
	palette = ui.get_node("Panel/VBox/Palette")
	status = ui.get_node("Panel/VBox/Status")
	help = ui.get_node("HelpPanel/VBox/Help")
	help_button = Button.new()
	help_button.text = "?"
	help_button.tooltip_text = "Planning controls"
	help_button.custom_minimum_size = Vector2(36, 36)
	ui.add_child(help_button)
	help_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help_button.position = Vector2(-52, 8)
	help_button.pressed.connect(view._toggle_help)
	ui.get_node("HelpPanel/VBox/Close").pressed.connect(view._toggle_help)
	light_info = ui.get_node("Panel/VBox/LightInfo")
	light_level = ui.get_node("Panel/VBox/LightLevel")
	light_angle_info = ui.get_node("Panel/VBox/LightAngleInfo")
	light_angle = ui.get_node("Panel/VBox/LightAngle")
	light_defaults = ui.get_node("Panel/VBox/LightDefaults")
	default_light_height = ui.get_node("Panel/VBox/LightDefaults/HeightRow/Value")
	default_light_energy = ui.get_node("Panel/VBox/LightDefaults/EnergyRow/Value")
	default_light_angle = ui.get_node("Panel/VBox/LightDefaults/AngleRow/Value")
	default_flicker_mode = ui.get_node("Panel/VBox/LightDefaults/FlickerRow/Mode")
	default_flicker_step = ui.get_node("Panel/VBox/LightDefaults/FlickerStepRow/Value")
	selected_flicker_mode = ui.get_node("Panel/VBox/SelectedFlicker/Mode")
	selected_flicker_step = ui.get_node("Panel/VBox/SelectedFlickerStep/Value")
	default_flicker_mode.item_selected.connect(view._on_default_flicker_mode_changed)
	selected_flicker_mode.item_selected.connect(view._on_selected_flicker_changed)
	selected_flicker_step.value_changed.connect(view._on_selected_flicker_step_changed)
	map_name_edit = ui.get_node("Panel/VBox/MapManager/Name")
	map_select = ui.get_node("Panel/VBox/MapManager/Maps")
	hud_nodes = [
		host.get_node("PrototypeHUD"),
		host.get_node("Crosshair"),
		host.get_node("Radar"),
		host.get_node_or_null("FogOfWar")
	]
	catalog._build_environment_catalogs()
	active_catalog = group_catalogs["01"]
	catalog._rebuild_palette()
	palette.item_selected.connect(catalog._on_palette_selected)
	desk_setup_button = Button.new()
	desk_setup_button.text = "Plan desk setup"
	desk_setup_button.visible = false
	ui.get_node("Panel/VBox").add_child(desk_setup_button)
	ui.get_node("Panel/VBox").move_child(desk_setup_button, palette.get_index() + 1)
	desk_setup_button.pressed.connect(view._open_desk_setup)
	desk_setup = DESK_SETUP_MODE.new()
	add_child(desk_setup)
	desk_setup.configure(self, ui)
	view._build_planning_toolbar()
	ui.get_node("Panel/VBox/Tabs/Structure").pressed.connect(catalog._show_structure_catalog)
	ui.get_node("Panel/VBox/Tabs/Actors").pressed.connect(catalog._show_actor_catalog)
	ui.get_node("Panel/VBox/Tabs/Lighting").pressed.connect(catalog._show_lighting_catalog)
	for group_name in ["01","02","03","04","05","06","07","08","09","10","11","12","13"]:
		var button := ui.get_node("Panel/VBox/GroupTabs/G" + group_name) as Button
		button.pressed.connect(catalog._show_structure_group.bind(group_name))
	ui.get_node("Panel/VBox/MapManager/Buttons/SaveMap").pressed.connect(storage.save_named_map)
	ui.get_node("Panel/VBox/MapManager/Buttons/LoadMap").pressed.connect(storage.load_selected_map)
	ui.get_node("Panel/VBox/Save").pressed.connect(storage.save_layout)
	ui.get_node("Panel/VBox/Clear").pressed.connect(objects.clear_layout)
	ui.get_node("Panel/VBox/Close").pressed.connect(exit)
	ui.hide()
	objects._register_existing_scene_objects()
	objects._register_actor_objects()
	storage._ensure_maps_dir()
	storage._refresh_map_list()
	storage.load_layout()


func enter() -> void:
	active = true
	edit_history.set("stack", [])
	view._update_history_buttons()
	help.get_parent().get_parent().hide()
	help_button.show()
	workstation_transforms.clear()
	var planning_lighting := host.get_node_or_null("PlanningLighting")
	if planning_lighting != null:
		planning_lighting.call("set_planning_mode", true)
	saved_camera_transform = camera.transform
	saved_camera_rig_transform = camera_rig.transform
	planning_yaw = camera.global_rotation.y
	planning_pitch = camera.global_rotation.x
	camera_yaw = planning_yaw
	camera_pitch = planning_pitch
	view._reset_selection()
	view._show_planning_grid()
	var chunk_streamer := host.get_node_or_null("ChunkStreamer")
	if chunk_streamer != null:
		chunk_streamer.call("set_runtime_enabled", false)
	view._set_light_markers_visible(true)
	for node in hud_nodes:
		if node != null:
			node.hide()
	var mutation_hud := host.get("mutation_tree_ui") as CanvasLayer
	if mutation_hud != null:
		mutation_hud.hide()
	get_tree().paused = true
	ui.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera_anchor = camera.global_position
	camera_height = clampf(camera.global_position.y, CAMERA_MIN_HEIGHT, CAMERA_MAX_HEIGHT)
	help.text = "PLANNING CONTROLS\n\nWASD  Move view\nALT + LMB drag  Rotate view (look up or down)\nWheel  Raise / lower camera, including below floor\nLMB  Select / Place\nLMB drag  Move selected\nRMB  Cancel current tool\nDelete  Delete selected\nQ / E  Rotate -/+15°\nR  Rotate +90°\n+ / -  Uniform scale\nX / Z  X size +/-\nC / V  Z size +/-\nArrow keys  Move selected on plane\nPgUp / PgDn  Move object up/down\n[ / ]  Light brightness\n, / .  Light cone angle\nESC  Exit planner"
	status.text = "Choose an object"


func exit() -> void:
	if desk_setup.active:
		desk_setup.close()
	active = false
	help.get_parent().get_parent().hide()
	help_button.hide()
	var planning_lighting := host.get_node_or_null("PlanningLighting")
	if planning_lighting != null:
		planning_lighting.call("set_planning_mode", false)
	var chunk_streamer := host.get_node_or_null("ChunkStreamer")
	if chunk_streamer != null:
		chunk_streamer.call("rebuild")
		chunk_streamer.call("set_runtime_enabled", true)
	objects._activate_all_enemies()
	camera_rig.transform = saved_camera_rig_transform
	camera.transform = saved_camera_transform
	for node in hud_nodes:
		if node != null:
			node.show()
	var mutation_hud := host.get("mutation_tree_ui") as CanvasLayer
	if mutation_hud != null:
		mutation_hud.show()
	objects._clear_preview()
	view._set_light_markers_visible(false)
	view._hide_planning_grid()
	view._select(null)
	ui.hide()
	get_tree().paused = false


func _process(delta: float) -> void:
	if not active:
		return
	objects._sync_workstations()
	if desk_setup.active:
		return
	if view._text_field_has_focus():
		return
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input.y += 1.0
	if Input.is_key_pressed(KEY_S): input.y -= 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if input.length_squared() > 0.0:
		input = input.normalized()
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var move := (right * input.x + forward * input.y) * CAMERA_SPEED * delta
		camera.global_position += move
		camera_anchor += move


func _input(event: InputEvent) -> void:
	if not active:
		return
	if desk_setup.active:
		if desk_setup.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse and planning_toolbar.get_global_rect().has_point(event.position):
		return
	if event is InputEventMouse and (ui.get_node("Panel") as Control).get_global_rect().has_point(event.position):
		# _input precedes GUI dispatch: let the palette receive this event.
		return
	# Allow both map names and SpinBox editors to receive keys before planner shortcuts.
	if view._text_field_has_focus() and event is InputEventKey:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			(get_viewport().gui_get_focus_owner() as Control).release_focus()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			objects._nudge_selected(Vector2(
				-1.0 if event.keycode == KEY_LEFT else (1.0 if event.keycode == KEY_RIGHT else 0.0),
				-1.0 if event.keycode == KEY_UP else (1.0 if event.keycode == KEY_DOWN else 0.0)
			))
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_ESCAPE:
				exit()
			KEY_DELETE:
				objects._delete_selected()
			KEY_Q:
				objects._rotate_selected(-15.0)
			KEY_E:
				objects._rotate_selected(15.0)
			KEY_R:
				objects._rotate_selected(90.0)
			KEY_EQUAL, KEY_KP_ADD:
				objects._scale_selected(Vector3.ONE * SCALE_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:
				objects._scale_selected(Vector3.ONE * -SCALE_STEP)
			KEY_X:
				objects._scale_selected(Vector3(SCALE_STEP, 0.0, 0.0))
			KEY_Z:
				objects._scale_selected(Vector3(-SCALE_STEP, 0.0, 0.0))
			KEY_C:
				objects._scale_selected(Vector3(0.0, 0.0, SCALE_STEP))
			KEY_V:
				objects._scale_selected(Vector3(0.0, 0.0, -SCALE_STEP))
			KEY_PAGEUP:
				objects._move_selected_height(HEIGHT_STEP)
			KEY_PAGEDOWN:
				objects._move_selected_height(-HEIGHT_STEP)
			KEY_BRACKETLEFT:
				objects._adjust_selected_light(-0.25)
			KEY_BRACKETRIGHT:
				objects._adjust_selected_light(0.25)
			KEY_COMMA:
				objects._adjust_selected_light_angle(-4.0)
			KEY_PERIOD:
				objects._adjust_selected_light_angle(4.0)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_drag_recorded = false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			geometry._zoom_camera(-CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			geometry._zoom_camera(CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			objects._click_world(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			view._reset_selection()
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.is_key_pressed(KEY_ALT):
			geometry._rotate_camera(event.relative)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and selected != null:
			var world := geometry._screen_to_floor(event.position)
			if world.is_finite():
				if not _drag_recorded:
					edit_history.call("record_transform", selected)
					_drag_recorded = true
				var locked_y := selected.global_position.y
				selected.global_position = geometry._snap_position_for(selected, world)
				if geometry._is_ceiling_tool(selected):
					selected.global_position.y = locked_y
				view._update_status()
		elif preview != null:
			objects._update_preview(event.position)


func _instantiate_asset(asset_path: String) -> Node3D:
	return catalog._instantiate_asset(asset_path)


func _clear_preview() -> void:
	objects._clear_preview()


func _clear_selection_highlight() -> void:
	view._clear_selection_highlight()


func _select(node: Node3D) -> void:
	view._select(node)


func _planned_object_at(screen_pos: Vector2) -> Node3D:
	return objects._planned_object_at(screen_pos)


func _delete_node(node: Node3D) -> void:
	objects._delete_node(node)


func _sync_workstations() -> void:
	objects._sync_workstations()


func _update_history_buttons() -> void:
	view._update_history_buttons()


func _apply_layout_data(data: Dictionary) -> void:
	storage._apply_layout_data(data)


func _collect_layout_data() -> Dictionary:
	return storage._collect_layout_data()


func _adjust_selected_light(amount: float) -> void:
	objects._adjust_selected_light(amount)


func _apply_new_light_defaults(node: Node3D) -> void:
	geometry._apply_new_light_defaults(node)
