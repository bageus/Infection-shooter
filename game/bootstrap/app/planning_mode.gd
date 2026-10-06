extends Node

const OBJECTS := preload("res://game/bootstrap/app/planning_objects.gd")
const GEOMETRY := preload("res://game/bootstrap/app/planning_geometry.gd")
const CONTROLS := preload("res://game/bootstrap/app/planning_controls.gd")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")

const CAMERA_SPEED := 18.0
const CAMERA_ZOOM_STEP := 2.5
const CAMERA_MIN_HEIGHT := -15.0
const CAMERA_MAX_HEIGHT := 55.0
const SCALE_STEP := 0.1
const HEIGHT_STEP := 0.25
const CAMERA_ROTATE_SPEED := 0.008
const DESK_SETUP_MODE := preload("res://game/bootstrap/app/desk_setup_mode.gd")
const EDIT_HISTORY := preload("res://game/bootstrap/app/planning_edit_history.gd")

var host: Node3D
var camera: Camera3D
var root: Node3D
var structure_root: Node3D
var gameplay_root: Node3D
var enemies_root: Node3D
var main_player: Node3D
var ui: Control
var hud_nodes: Array[Node] = []
var active := false
var camera_anchor := Vector3.ZERO
var camera_height := 24.0
var saved_camera_transform := Transform3D.IDENTITY
var saved_camera_rig_transform := Transform3D.IDENTITY
var camera_rig: Node3D
var camera_yaw := 0.0
var camera_pitch := -0.75
var planning_yaw := 0.0
var planning_pitch := -0.75
var desk_setup: Node
var edit_history: RefCounted
var _drag_recorded := false

var objects = OBJECTS.new()
var geometry = GEOMETRY.new()
var controls = CONTROLS.new()
var catalog = CATALOG.new()
var storage = STORAGE.new()


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
	var context := {"session": self, "objects": objects, "geometry": geometry,
		"controls": controls, "catalog": catalog, "storage": storage}
	for component in [objects, geometry, controls, storage]:
		component.configure(context)
	add_child(objects)
	add_child(controls)
	edit_history = EDIT_HISTORY.new()
	edit_history.set("planner", self)
	controls.setup_controls()
	storage.setup_widgets()
	hud_nodes = [
		host.get_node("PrototypeHUD"),
		host.get_node("Crosshair"),
		host.get_node("Radar"),
		host.get_node_or_null("FogOfWar")
	]
	catalog.bind_asset = Callable(host, "bind_world_object")
	catalog._build_environment_catalogs()
	catalog.active_catalog = catalog.group_catalogs["01"]
	controls._rebuild_palette()
	controls.palette.item_selected.connect(objects._on_palette_selected)
	desk_setup = DESK_SETUP_MODE.new()
	add_child(desk_setup)
	desk_setup.configure(self, ui)
	ui.get_node("Panel/VBox/Tabs/Structure").pressed.connect(controls._show_structure_catalog)
	ui.get_node("Panel/VBox/Tabs/Actors").pressed.connect(controls._show_actor_catalog)
	ui.get_node("Panel/VBox/Tabs/Lighting").pressed.connect(controls._show_lighting_catalog)
	for group_name in ["01","02","03","04","05","06","07","08","09","10","11","12","13"]:
		var button := ui.get_node("Panel/VBox/GroupTabs/G" + group_name) as Button
		button.pressed.connect(controls._show_structure_group.bind(group_name))
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
	preload("res://game/bootstrap/app/planning_physics.gd").resume(objects.placed)


func enter() -> void:
	active = true
	_set_occlusion_enabled(false)
	# The planner edits the authored map, not what the fight left of it.
	var restored: bool = storage.restore_authored()
	edit_history.set("stack", [])
	controls._update_history_buttons()
	controls.help.get_parent().get_parent().hide()
	controls.help_button.show()
	objects.workstation_transforms.clear()
	var planning_lighting := host.get_node_or_null("PlanningLighting")
	if planning_lighting != null:
		planning_lighting.call("set_planning_mode", true)
	saved_camera_transform = camera.transform
	saved_camera_rig_transform = camera_rig.transform
	planning_yaw = camera.global_rotation.y
	planning_pitch = camera.global_rotation.x
	camera_yaw = planning_yaw
	camera_pitch = planning_pitch
	objects._reset_selection()
	geometry._show_planning_grid()
	var chunk_streamer := host.get_node_or_null("ChunkStreamer")
	if chunk_streamer != null:
		chunk_streamer.call("set_runtime_enabled", false)
	_set_light_markers_visible(true)
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
	controls.help.text = "PLANNING CONTROLS\n\nWASD  Move view\nALT + LMB drag  Rotate view (look up or down)\nWheel  Raise / lower camera, including below floor\nLMB  Select / Place\nLMB drag  Move selected\nRMB  Cancel current tool\nDelete  Delete selected\nQ / E  Rotate -/+15°\nR  Rotate +90°\n+ / -  Uniform scale\nX / Z  X size +/-\nC / V  Z size +/-\nArrow keys  Move selected on plane\nPgUp / PgDn  Move object up/down\n[ / ]  Light brightness\n, / .  Light cone angle\nESC  Exit planner"
	controls.status.text = "Map restored to its saved layout — choose an object" if restored else "Choose an object"


func exit() -> void:
	if desk_setup.active:
		desk_setup.close()
	storage.snapshot_authored()
	active = false
	_set_occlusion_enabled(true)
	controls.help.get_parent().get_parent().hide()
	controls.help_button.hide()
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
	_set_light_markers_visible(false)
	geometry._hide_planning_grid()
	objects._select(null)
	ui.hide()
	preload("res://game/bootstrap/app/planning_physics.gd").resume(objects.placed)
	get_tree().paused = false


func _process(delta: float) -> void:
	if not active:
		return
	objects._sync_workstations()
	if desk_setup.active:
		return
	if _text_field_has_focus():
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
	if event is InputEventMouse and controls.planning_toolbar.get_global_rect().has_point(event.position):
		return
	if event is InputEventMouse and (ui.get_node("Panel") as Control).get_global_rect().has_point(event.position):
		# _input precedes GUI dispatch: let the palette receive this event.
		return
	# Allow both map names and SpinBox editors to receive keys before planner shortcuts.
	if _text_field_has_focus() and event is InputEventKey:
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
				controls._adjust_selected_light(-0.25)
			KEY_BRACKETRIGHT:
				controls._adjust_selected_light(0.25)
			KEY_COMMA:
				controls._adjust_selected_light_angle(-4.0)
			KEY_PERIOD:
				controls._adjust_selected_light_angle(4.0)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_drag_recorded = false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera(-CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera(CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			objects._click_world(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			objects._reset_selection()
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.is_key_pressed(KEY_ALT):
			_rotate_camera(event.relative)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and objects.selected != null:
			if not _drag_recorded:
				edit_history.call("record_transform", objects.selected)
				_drag_recorded = true
			objects._drag_selected(event.position)
		elif objects.preview != null:
			objects._update_preview(event.position)


func _text_field_has_focus() -> bool:
	# Any text entry (map name, spin boxes, the blood size field) keeps its keys.
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func _rotate_camera(relative: Vector2) -> void:
	planning_yaw -= relative.x * CAMERA_ROTATE_SPEED
	planning_pitch = clampf(planning_pitch - relative.y * CAMERA_ROTATE_SPEED, deg_to_rad(-80.0), deg_to_rad(80.0))
	var current_position := camera.global_position
	camera.global_rotation = Vector3(planning_pitch, planning_yaw, 0.0)
	camera.global_position = current_position


func _zoom_camera(amount: float) -> void:
	camera_height = clampf(camera_height + amount, CAMERA_MIN_HEIGHT, CAMERA_MAX_HEIGHT)
	var p := camera.global_position
	p.y = camera_height
	camera.global_position = p


func _set_light_markers_visible(value: bool) -> void:
	for light_node in get_tree().get_nodes_in_group("planner_lights"):
		if light_node.has_method("set_planning_visual"):
			light_node.call("set_planning_visual", value)

var player_spawn_defined: bool:
	get:
		return objects.player_spawn_defined
	set(value):
		objects.player_spawn_defined = value

var player_spawn_transform: Transform3D:
	get:
		return objects.player_spawn_transform
	set(value):
		objects.player_spawn_transform = value

var selected_path: String:
	get:
		return objects.selected_path
	set(value):
		objects.selected_path = value

var selected_kind: String:
	get:
		return objects.selected_kind
	set(value):
		objects.selected_kind = value

var preview: Node3D:
	get:
		return objects.preview
	set(value):
		objects.preview = value

var selected: Node3D:
	get:
		return objects.selected
	set(value):
		objects.selected = value

var rotation_y: float:
	get:
		return objects.rotation_y
	set(value):
		objects.rotation_y = value

var placed: Array[Node3D]:
	get:
		return objects.placed
	set(value):
		objects.placed = value

var workstation_transforms: Dictionary:
	get:
		return objects.workstation_transforms
	set(value):
		objects.workstation_transforms = value

var palette: ItemList:
	get:
		return controls.palette

var status: Label:
	get:
		return controls.status

var help: Label:
	get:
		return controls.help

var help_button: Button:
	get:
		return controls.help_button

var desk_setup_button: Button:
	get:
		return controls.desk_setup_button

var planning_toolbar: PanelContainer:
	get:
		return controls.planning_toolbar


func _select(node: Node3D) -> void:
	objects._select(node)


func _clear_preview() -> void:
	objects._clear_preview()


func _delete_node(node: Node3D) -> void:
	objects._delete_node(node)


func _sync_workstations() -> void:
	objects._sync_workstations()


func _update_status() -> void:
	objects._update_status()


func clear_layout(update_status: bool = true) -> void:
	objects.clear_layout(update_status)


func _instantiate_asset(asset_path: String) -> Node3D:
	return catalog._instantiate_asset(asset_path)


func _planned_object_at(screen_pos: Vector2) -> Node3D:
	return geometry._planned_object_at(screen_pos)


func _clear_selection_highlight() -> void:
	geometry._clear_selection_highlight()


func _update_history_buttons() -> void:
	controls._update_history_buttons()


func _set_occlusion_enabled(value: bool) -> void:
	var effects := host.get_node_or_null("OcclusionEffects")
	if effects != null:
		effects.call("set_runtime_enabled", value)
