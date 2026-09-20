extends Node

const SAVE_PATH := "user://planned_layout.json"
const GRID_SIZE := 1.0

var host: Node3D
var camera: Camera3D
var root: Node3D
var ui: Control
var palette: ItemList
var status: Label
var active := false
var selected_path := ""
var preview: Node3D
var rotation_y := 0.0
var placed: Array[Node3D] = []

var catalog := [
	{"name":"Window Double","path":"res://game/presentation/office_floor/public/structural/window_double.tscn"},
	{"name":"Window Corner","path":"res://game/presentation/office_floor/public/structural/window_corner.tscn"},
	{"name":"Wall Straight","path":"res://game/presentation/office_floor/public/structural/wall_straight.tscn"},
	{"name":"Wall Half","path":"res://game/presentation/office_floor/public/structural/wall_half_panel.tscn"},
	{"name":"Inner Corner","path":"res://game/presentation/office_floor/public/structural/wall_inner_corner.tscn"},
	{"name":"Outer Corner","path":"res://game/presentation/office_floor/public/structural/wall_outer_corner.tscn"},
	{"name":"Door Wall","path":"res://game/presentation/office_floor/public/structural/wall_door.tscn"},
	{"name":"Emergency Door","path":"res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn"},
	{"name":"Column","path":"res://game/presentation/office_floor/public/structural/column.tscn"}
]


func setup(owner: Node3D, planning_root: Node3D, planning_ui: Control) -> void:
	host = owner
	root = planning_root
	ui = planning_ui
	camera = host.get_node("Gameplay/Player/CameraRig/Camera3D")
	palette = ui.get_node("Panel/VBox/Palette")
	status = ui.get_node("Panel/VBox/Status")
	palette.clear()
	for entry: Dictionary in catalog:
		palette.add_item(str(entry.get("name", "")))
	palette.item_selected.connect(_on_palette_selected)
	ui.get_node("Panel/VBox/Save").pressed.connect(save_layout)
	ui.get_node("Panel/VBox/Clear").pressed.connect(clear_layout)
	ui.get_node("Panel/VBox/Close").pressed.connect(exit)
	ui.hide()
	load_layout()


func enter() -> void:
	active = true
	get_tree().paused = true
	ui.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status.text = "LMB place | RMB delete | R rotate | grid 1m"


func exit() -> void:
	active = false
	_clear_preview()
	ui.hide()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			exit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_R:
			rotation_y = fmod(rotation_y + 90.0, 360.0)
			if preview != null:
				preview.rotation_degrees.y = rotation_y
	if event is InputEventMouseMotion:
		_update_preview(event.position)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_selected(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_delete_at(event.position)


func _on_palette_selected(index: int) -> void:
	var entry: Dictionary = catalog[index]
	selected_path = str(entry.get("path", ""))
	rotation_y = 0.0
	_rebuild_preview()


func _rebuild_preview() -> void:
	_clear_preview()
	if selected_path.is_empty():
		return
	var scene := load(selected_path) as PackedScene
	if scene == null:
		return
	preview = scene.instantiate() as Node3D
	host.add_child(preview)
	_set_preview_collision(preview, true)


func _clear_preview() -> void:
	if preview != null and is_instance_valid(preview):
		preview.queue_free()
	preview = null


func _update_preview(screen_pos: Vector2) -> void:
	if preview == null:
		return
	var world: Vector3 = _screen_to_floor(screen_pos)
	if not world.is_finite():
		return
	preview.global_position = _snap(world)
	preview.rotation_degrees.y = rotation_y


func _place_selected(screen_pos: Vector2) -> void:
	if selected_path.is_empty():
		return
	var world: Vector3 = _screen_to_floor(screen_pos)
	if not world.is_finite():
		return
	var scene := load(selected_path) as PackedScene
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	root.add_child(node)
	node.global_position = _snap(world)
	node.rotation_degrees.y = rotation_y
	node.set_meta("planning_scene_path", selected_path)
	placed.append(node)
	status.text = "%d placed | unsaved" % placed.size()


func _delete_at(screen_pos: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_pos)
	var end := origin + camera.project_ray_normal(screen_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var node := hit.get("collider") as Node
	while node != null and node.get_parent() != root:
		node = node.get_parent()
	if node != null and node.get_parent() == root:
		placed.erase(node)
		node.queue_free()
		status.text = "%d placed | unsaved" % placed.size()


func _screen_to_floor(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return Vector3(INF, INF, INF)
	var distance: float = -origin.y / direction.y
	if distance < 0.0:
		return Vector3(INF, INF, INF)
	return origin + direction * distance


func _snap(value: Vector3) -> Vector3:
	return Vector3(
		roundf(value.x / GRID_SIZE) * GRID_SIZE,
		0.0,
		roundf(value.z / GRID_SIZE) * GRID_SIZE
	)


func save_layout() -> void:
	var objects: Array = []
	for node in placed:
		if not is_instance_valid(node):
			continue
		objects.append({
			"scene": str(node.get_meta("planning_scene_path", "")),
			"x": node.position.x,
			"z": node.position.z,
			"rotation_y": node.rotation_degrees.y
		})
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		status.text = "SAVE FAILED"
		return
	file.store_string(JSON.stringify({"version":1,"objects":objects}, "\t"))
	status.text = "SAVED: %s" % SAVE_PATH


func load_layout() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.has("objects"):
		return
	clear_layout(false)
	var records: Array = data.get("objects", [])
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var scene := load(str(record.get("scene", ""))) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate() as Node3D
		root.add_child(node)
		node.position = Vector3(float(record.get("x",0.0)),0.0,float(record.get("z",0.0)))
		node.rotation_degrees.y = float(record.get("rotation_y",0.0))
		node.set_meta("planning_scene_path", str(record.get("scene","")))
		placed.append(node)


func clear_layout(update_status: bool = true) -> void:
	for node in placed:
		if is_instance_valid(node):
			node.queue_free()
	placed.clear()
	if update_status:
		status.text = "Layout cleared"


func _set_preview_collision(node: Node, disabled: bool) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = disabled
	for child in node.get_children():
		_set_preview_collision(child, disabled)
