extends Node

const SAVE_PATH := "user://planned_layout.json"
const GRID_SIZE := 0.25
const SNAP_DISTANCE := 0.8
const CAMERA_SPEED := 18.0
const CAMERA_ZOOM_STEP := 2.5
const SCALE_STEP := 0.1

var host: Node3D
var camera: Camera3D
var root: Node3D
var structure_root: Node3D
var ui: Control
var palette: ItemList
var status: Label
var help: Label
var hud_nodes: Array[Node] = []
var active := false
var selected_path := ""
var preview: Node3D
var selected: Node3D
var rotation_y := 0.0
var last_mouse_world := Vector3.ZERO
var placed: Array[Node3D] = []
var camera_anchor := Vector3.ZERO
var camera_height := 24.0

var catalog := [
	{"name":"Window Double","path":"res://game/presentation/office_floor/public/structural/window_double.tscn"},
	{"name":"Window Corner","path":"res://game/presentation/office_floor/public/structural/window_corner.tscn"},
	{"name":"Wall Straight","path":"res://game/presentation/office_floor/public/structural/wall_straight.tscn"},
	{"name":"Wall Half","path":"res://game/presentation/office_floor/public/structural/wall_half_panel.tscn"},
	{"name":"Outer Corner","path":"res://game/presentation/office_floor/public/structural/wall_outer_corner.tscn"},
	{"name":"Door Wall","path":"res://game/presentation/office_floor/public/structural/wall_door.tscn"},
	{"name":"Emergency Door","path":"res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn"},
	{"name":"Column","path":"res://game/presentation/office_floor/public/structural/column.tscn"},
	{"name":"Floor Pad","path":"res://game/presentation/office_floor/public/structural/floor_pad.tscn"},
	{"name":"Elevator Passenger","path":"res://game/presentation/office_floor/public/structural/elevator_cabin_passenger.tscn"},
	{"name":"Elevator Freight","path":"res://game/presentation/office_floor/public/structural/elevator_cabin_freight.tscn"},
	{"name":"Elevator Door","path":"res://game/presentation/office_floor/public/structural/elevator_door.tscn"},
	{"name":"Door Wall 3","path":"res://game/presentation/office_floor/public/structural/wall_door_3.tscn"}
]


func setup(owner: Node3D, planning_root: Node3D, planning_ui: Control) -> void:
	host = owner
	root = planning_root
	structure_root = host.get_node("Structure")
	ui = planning_ui
	camera = host.get_node("Gameplay/Player/CameraRig/Camera3D")
	palette = ui.get_node("Panel/VBox/Palette")
	status = ui.get_node("Panel/VBox/Status")
	help = ui.get_node("HelpPanel/Help")
	hud_nodes = [
		host.get_node("PrototypeHUD"),
		host.get_node("Crosshair"),
		host.get_node("Radar")
	]
	palette.clear()
	for entry: Dictionary in catalog:
		palette.add_item(str(entry.get("name", "")))
	palette.item_selected.connect(_on_palette_selected)
	ui.get_node("Panel/VBox/Save").pressed.connect(save_layout)
	ui.get_node("Panel/VBox/Clear").pressed.connect(clear_layout)
	ui.get_node("Panel/VBox/Close").pressed.connect(exit)
	ui.hide()
	_register_existing_scene_objects()
	load_layout()


func enter() -> void:
	active = true
	_reset_selection()
	for node in hud_nodes:
		node.hide()
	get_tree().paused = true
	ui.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera_anchor = camera.global_position
	camera_height = clampf(camera.global_position.y, 8.0, 50.0)
	help.text = "PLANNING CONTROLS\n\nWASD  Move view\nWheel  Zoom\nLMB  Select / Place\nLMB drag  Move selected\nRMB  Cancel current tool\nDelete  Delete selected\nQ / E  Rotate -/+15°\nR  Rotate +90°\n+ / -  Uniform scale\nX / Z  X size +/-\nC / V  Z size +/-\nESC  Exit planner"
	status.text = "Choose an object | matching edges snap automatically"


func exit() -> void:
	active = false
	for node in hud_nodes:
		node.show()
	_clear_preview()
	_select(null)
	ui.hide()
	get_tree().paused = false


func _process(delta: float) -> void:
	if not active:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_key_pressed(KEY_S): move.z += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if move.length_squared() > 0.0:
		move = move.normalized() * CAMERA_SPEED * delta
		camera.global_position += move
		camera_anchor += move


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				exit()
			KEY_DELETE:
				_delete_selected()
			KEY_Q:
				_rotate_selected(-15.0)
			KEY_E:
				_rotate_selected(15.0)
			KEY_R:
				_rotate_selected(90.0)
			KEY_EQUAL, KEY_KP_ADD:
				_scale_selected(Vector3.ONE * SCALE_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_scale_selected(Vector3.ONE * -SCALE_STEP)
			KEY_X:
				_scale_selected(Vector3(SCALE_STEP, 0.0, 0.0))
			KEY_Z:
				_scale_selected(Vector3(-SCALE_STEP, 0.0, 0.0))
			KEY_C:
				_scale_selected(Vector3(0.0, 0.0, SCALE_STEP))
			KEY_V:
				_scale_selected(Vector3(0.0, 0.0, -SCALE_STEP))
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera(-CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera(CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_click_world(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_reset_selection()
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and selected != null:
			var world := _screen_to_floor(event.position)
			if world.is_finite():
				selected.global_position = _snap_position_for(selected, world)
				_update_status()
		elif preview != null:
			_update_preview(event.position)


func _reset_selection() -> void:
	selected_path = ""
	rotation_y = 0.0
	_clear_preview()
	_select(null)
	palette.deselect_all()
	status.text = "Selection cleared | choose palette item or click placed object"


func _on_palette_selected(index: int) -> void:
	var entry: Dictionary = catalog[index]
	selected_path = str(entry.get("path", ""))
	rotation_y = 0.0
	_select(null)
	_rebuild_preview()


func _click_world(screen_pos: Vector2) -> void:
	var hit_node := _planned_object_at(screen_pos)
	if hit_node != null:
		_select(hit_node)
		_clear_preview()
		return
	if not selected_path.is_empty():
		_place_selected(screen_pos)
	else:
		_select(null)


func _select(node: Node3D) -> void:
	if selected != null and is_instance_valid(selected):
		selected.scale = selected.scale
	selected = node
	_update_status()


func _register_existing_scene_objects() -> void:
	_register_editable_children(structure_root)


func _register_editable_children(parent: Node) -> void:
	for child in parent.get_children():
		if child is Node3D:
			var node := child as Node3D
			if _is_editable_scene_object(node):
				if not placed.has(node):
					placed.append(node)
				node.set_meta("planning_existing", true)
			else:
				_register_editable_children(node)


func _is_editable_scene_object(node: Node3D) -> bool:
	if node == root or node == structure_root:
		return false
	return _find_collision_descendant(node) != null and node.get_parent() != host


func _find_collision_descendant(node: Node) -> CollisionObject3D:
	if node is CollisionObject3D:
		return node as CollisionObject3D
	for child in node.get_children():
		var found := _find_collision_descendant(child)
		if found != null:
			return found
	return null


func _editable_root_from_collider(collider: Node) -> Node3D:
	var node: Node = collider
	while node != null:
		if node.get_parent() == root:
			return node as Node3D
		if node is Node3D and placed.has(node):
			return node as Node3D
		if node.get_parent() == structure_root:
			return node as Node3D
		node = node.get_parent()
	return null


func _planned_object_at(screen_pos: Vector2) -> Node3D:
	var origin := camera.project_ray_origin(screen_pos)
	var end := origin + camera.project_ray_normal(screen_pos) * 300.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit.get("collider") as Node
	if collider == null:
		return null
	return _editable_root_from_collider(collider)


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
	var world := _screen_to_floor(screen_pos)
	if not world.is_finite():
		return
	preview.global_position = _snap_position_for(preview, world)
	preview.rotation_degrees.y = rotation_y


func _place_selected(screen_pos: Vector2) -> void:
	var world := _screen_to_floor(screen_pos)
	if not world.is_finite():
		return
	var scene := load(selected_path) as PackedScene
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	root.add_child(node)
	node.global_position = _snap_position_for(node, world)
	node.rotation_degrees.y = rotation_y
	node.set_meta("planning_scene_path", selected_path)
	placed.append(node)
	_select(null)
	_rebuild_preview()
	preview.global_position = _snap_position_for(preview, world)
	preview.rotation_degrees.y = rotation_y
	status.text = "Placed | same object remains active | RMB cancel"


func _delete_at(screen_pos: Vector2) -> void:
	var node := _planned_object_at(screen_pos)
	if node != null:
		_delete_node(node)


func _delete_selected() -> void:
	if selected != null:
		_delete_node(selected)


func _delete_node(node: Node3D) -> void:
	placed.erase(node)
	if selected == node:
		selected = null
	node.queue_free()
	_update_status()


func _rotate_selected(amount: float) -> void:
	if selected != null:
		selected.rotation_degrees.y = fmod(selected.rotation_degrees.y + amount + 360.0, 360.0)
	elif preview != null:
		rotation_y = fmod(rotation_y + amount + 360.0, 360.0)
		preview.rotation_degrees.y = rotation_y
	_update_status()


func _scale_selected(delta_scale: Vector3) -> void:
	if selected == null:
		return
	var next := selected.scale + delta_scale
	next.x = maxf(next.x, 0.1)
	next.y = maxf(next.y, 0.1)
	next.z = maxf(next.z, 0.1)
	selected.scale = next
	_update_status()


func _zoom_camera(amount: float) -> void:
	camera_height = clampf(camera_height + amount, 6.0, 55.0)
	var p := camera.global_position
	p.y = camera_height
	camera.global_position = p


func _screen_to_floor(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return Vector3(INF, INF, INF)
	var distance := -origin.y / direction.y
	if distance < 0.0:
		return Vector3(INF, INF, INF)
	return origin + direction * distance


func _snap_position_for(node: Node3D, value: Vector3) -> Vector3:
	var base := _snap(value)
	var source_aabb := _combined_aabb(node)
	if source_aabb.size.length_squared() <= 0.0001:
		return base
	var best := base
	var best_distance := SNAP_DISTANCE
	var source_center := base + Vector3(source_aabb.position.x + source_aabb.size.x * 0.5, 0.0, source_aabb.position.z + source_aabb.size.z * 0.5)
	var source_half := Vector2(source_aabb.size.x * absf(node.scale.x) * 0.5, source_aabb.size.z * absf(node.scale.z) * 0.5)
	for other in placed:
		if other == node or not is_instance_valid(other):
			continue
		var other_aabb := _combined_aabb(other)
		if other_aabb.size.length_squared() <= 0.0001:
			continue
		var other_center := other.global_position + Vector3(other_aabb.position.x + other_aabb.size.x * 0.5, 0.0, other_aabb.position.z + other_aabb.size.z * 0.5)
		var other_half := Vector2(other_aabb.size.x * absf(other.scale.x) * 0.5, other_aabb.size.z * absf(other.scale.z) * 0.5)
		var candidates := [
			Vector3(other_center.x + other_half.x + source_half.x, 0.0, other_center.z),
			Vector3(other_center.x - other_half.x - source_half.x, 0.0, other_center.z),
			Vector3(other_center.x, 0.0, other_center.z + other_half.y + source_half.y),
			Vector3(other_center.x, 0.0, other_center.z - other_half.y - source_half.y)
		]
		for candidate: Vector3 in candidates:
			var distance := Vector2(candidate.x - source_center.x, candidate.z - source_center.z).length()
			if distance < best_distance:
				best_distance = distance
				best = base + Vector3(candidate.x - source_center.x, 0.0, candidate.z - source_center.z)
	return best


func _combined_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_transform := node.global_transform.affine_inverse() * mesh_instance.global_transform
		var aabb := local_transform * mesh_instance.get_aabb()
		if not found:
			result = aabb
			found = true
		else:
			result = result.merge(aabb)
	return result


func _snap(value: Vector3) -> Vector3:
	return Vector3(roundf(value.x / GRID_SIZE) * GRID_SIZE, 0.0, roundf(value.z / GRID_SIZE) * GRID_SIZE)


func _update_status() -> void:
	if selected == null:
		status.text = "%d objects | select palette or object" % placed.size()
		return
	status.text = "SELECTED | pos %.1f %.1f | rot %.0f | scale %.2f %.2f %.2f" % [
		selected.position.x, selected.position.z, selected.rotation_degrees.y,
		selected.scale.x, selected.scale.y, selected.scale.z
	]


func save_layout() -> void:
	var objects: Array = []
	for node in placed:
		if not is_instance_valid(node):
			continue
		var scene_path := str(node.get_meta("planning_scene_path", ""))
		if scene_path.is_empty():
			continue
		objects.append({
			"scene": str(node.get_meta("planning_scene_path", "")),
			"x": node.position.x, "y": node.position.y, "z": node.position.z,
			"rotation_y": node.rotation_degrees.y,
			"scale_x": node.scale.x, "scale_y": node.scale.y, "scale_z": node.scale.z
		})
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		status.text = "SAVE FAILED"
		return
	file.store_string(JSON.stringify({"version":2,"objects":objects}, "\t"))
	status.text = "SAVED | %d objects" % objects.size()


func load_layout() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
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
		node.position = Vector3(float(record.get("x",0.0)),float(record.get("y",0.0)),float(record.get("z",0.0)))
		node.rotation_degrees.y = float(record.get("rotation_y",0.0))
		node.scale = Vector3(float(record.get("scale_x",1.0)),float(record.get("scale_y",1.0)),float(record.get("scale_z",1.0)))
		node.set_meta("planning_scene_path", str(record.get("scene","")))
		placed.append(node)


func clear_layout(update_status: bool = true) -> void:
	var retained: Array[Node3D] = []
	for node in placed:
		if not is_instance_valid(node):
			continue
		if bool(node.get_meta("planning_existing", false)):
			retained.append(node)
		else:
			node.queue_free()
	placed = retained
	selected = null
	if update_status:
		_update_status()


func _set_preview_collision(node: Node, disabled: bool) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = disabled
	for child in node.get_children():
		_set_preview_collision(child, disabled)
