extends Node

const SAVE_PATH := "user://planned_layout.json"
const AUTHORED_SCENE_PATH := "res://game/levels/authored/base_office_layout.tscn"
const GRID_SIZE := 0.25
const SNAP_DISTANCE := 0.8
const CAMERA_SPEED := 18.0
const CAMERA_ZOOM_STEP := 2.5
const SCALE_STEP := 0.1
const CAMERA_ROTATE_SPEED := 0.008

var host: Node3D
var camera: Camera3D
var root: Node3D
var structure_root: Node3D
var gameplay_root: Node3D
var enemies_root: Node3D
var main_player: Node3D
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

var structure_catalog := [
	{"name":"Window Double","path":"res://game/presentation/office_floor/public/structural/window_double.tscn"},
	{"name":"Window Corner","path":"res://game/presentation/office_floor/public/structural/window_corner.tscn"},
	{"name":"Wall Straight","path":"res://game/presentation/office_floor/public/structural/wall_straight.tscn"},
	{"name":"Wall Half","path":"res://game/presentation/office_floor/public/structural/wall_half_panel.tscn"},
	{"name":"Outer Corner","path":"res://game/presentation/office_floor/public/structural/wall_outer_corner.tscn"},
	{"name":"Door Wall 2","path":"res://game/presentation/office_floor/public/structural/wall_door.tscn"},
	{"name":"Emergency Door","path":"res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn"},
	{"name":"Column","path":"res://game/presentation/office_floor/public/structural/column.tscn"},
	{"name":"Floor Pad","path":"res://game/presentation/office_floor/public/structural/floor_pad.tscn"},
	{"name":"Elevator Passenger","path":"res://game/presentation/office_floor/public/structural/elevator_cabin_passenger.tscn"},
	{"name":"Elevator Freight","path":"res://game/presentation/office_floor/public/structural/elevator_cabin_freight.tscn"},
	{"name":"Elevator Door","path":"res://game/presentation/office_floor/public/structural/elevator_door.tscn"},
	{"name":"Door Wall 3","path":"res://game/presentation/office_floor/public/structural/wall_door_3.tscn"},
	{"name":"Door Wall 2 Empty","path":"res://game/presentation/office_floor/public/structural/wall_door_2_without.tscn"},
	{"name":"Door Wall 3 Empty","path":"res://game/presentation/office_floor/public/structural/wall_door_3_without.tscn"},
	{"name":"Broken Door 2","path":"res://game/presentation/office_floor/public/structural/only_door_2.tscn"},
	{"name":"Broken Door 3","path":"res://game/presentation/office_floor/public/structural/only_door_3.tscn"}
]

var actor_catalog := [
	{"name":"Player Spawn","path":"","kind":"player"},
	{"name":"Infected","path":"res://game/features/infected/public/infected_capsule.tscn","kind":"enemy"}
]


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
	help = ui.get_node("HelpPanel/Help")
	hud_nodes = [
		host.get_node("PrototypeHUD"),
		host.get_node("Crosshair"),
		host.get_node("Radar")
	]
	active_catalog = structure_catalog
	_rebuild_palette()
	palette.item_selected.connect(_on_palette_selected)
	ui.get_node("Panel/VBox/Tabs/Structure").pressed.connect(_show_structure_catalog)
	ui.get_node("Panel/VBox/Tabs/Actors").pressed.connect(_show_actor_catalog)
	ui.get_node("Panel/VBox/Save").pressed.connect(save_layout)
	ui.get_node("Panel/VBox/Clear").pressed.connect(clear_layout)
	ui.get_node("Panel/VBox/Close").pressed.connect(exit)
	ui.hide()
	_register_existing_scene_objects()
	_register_actor_objects()
	load_layout()


func enter() -> void:
	active = true
	saved_camera_transform = camera.transform
	saved_camera_rig_transform = camera_rig.transform
	planning_yaw = camera.global_rotation.y
	planning_pitch = camera.global_rotation.x
	camera_yaw = planning_yaw
	camera_pitch = planning_pitch
	_reset_selection()
	_show_planning_grid()
	for node in hud_nodes:
		node.hide()
	get_tree().paused = true
	ui.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera_anchor = camera.global_position
	camera_height = clampf(camera.global_position.y, 8.0, 50.0)
	help.text = "PLANNING CONTROLS\n\nWASD  Move view\nALT + LMB drag  Rotate view\nWheel  Zoom\nLMB  Select / Place\nLMB drag  Move selected\nRMB  Cancel current tool\nDelete  Delete selected\nQ / E  Rotate -/+15°\nR  Rotate +90°\n+ / -  Uniform scale\nX / Z  X size +/-\nC / V  Z size +/-\nESC  Exit planner"
	status.text = "Choose an object"


func exit() -> void:
	active = false
	camera_rig.transform = saved_camera_rig_transform
	camera.transform = saved_camera_transform
	for node in hud_nodes:
		node.show()
	_clear_preview()
	_hide_planning_grid()
	_select(null)
	ui.hide()
	get_tree().paused = false


func _process(delta: float) -> void:
	if not active:
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
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.is_key_pressed(KEY_ALT):
			_rotate_camera(event.relative)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and selected != null:
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
	status.text = "Selection cleared"


func _rebuild_palette() -> void:
	palette.clear()
	for entry: Dictionary in active_catalog:
		palette.add_item(str(entry.get("name", "")))


func _show_structure_catalog() -> void:
	_reset_selection()
	active_catalog = structure_catalog
	_rebuild_palette()
	status.text = "STRUCTURE | choose building object"


func _show_actor_catalog() -> void:
	_reset_selection()
	active_catalog = actor_catalog
	_rebuild_palette()
	status.text = "ACTORS | place/remove Player and Infected"


func _show_planning_grid() -> void:
	if planning_grid != null and is_instance_valid(planning_grid):
		return
	planning_grid = MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 0.75, 1.0, 0.38)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var extent := 40
	var step := 1.0
	for i in range(-extent, extent + 1):
		var p := float(i) * step
		mesh.surface_add_vertex(Vector3(p, 0.012, -float(extent)))
		mesh.surface_add_vertex(Vector3(p, 0.012, float(extent)))
		mesh.surface_add_vertex(Vector3(-float(extent), 0.012, p))
		mesh.surface_add_vertex(Vector3(float(extent), 0.012, p))
	mesh.surface_end()
	planning_grid.mesh = mesh
	host.add_child(planning_grid)


func _hide_planning_grid() -> void:
	if planning_grid != null and is_instance_valid(planning_grid):
		planning_grid.queue_free()
	planning_grid = null


func _on_palette_selected(index: int) -> void:
	var entry: Dictionary = active_catalog[index]
	selected_path = str(entry.get("path", ""))
	if str(entry.get("kind", "")) == "player":
		selected_path = ""
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
	_clear_selection_highlight()
	selected = node
	if selected != null:
		_show_selection_highlight(selected)
	_update_status()


func _show_selection_highlight(node: Node3D) -> void:
	var aabb := _combined_aabb(node, true)
	selection_source_aabb = aabb
	if aabb.size.length_squared() <= 0.0001:
		return
	selection_box = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = aabb.size + Vector3(0.08, 0.08, 0.08)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 0.85, 1.0, 0.16)
	material.no_depth_test = true
	box.material = material
	selection_box.mesh = box
	selection_box.set_meta("planning_selection_highlight", true)
	node.add_child(selection_box)
	selection_box.position = aabb.get_center()


func _clear_selection_highlight() -> void:
	if selection_box != null and is_instance_valid(selection_box):
		selection_box.queue_free()
	selection_box = null
	selection_source_aabb = AABB()


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


func _register_actor_objects() -> void:
	if main_player != null and not placed.has(main_player):
		placed.append(main_player)
		main_player.set_meta("planning_actor_kind", "player")
		main_player.set_meta("planning_existing", true)
	for child in enemies_root.get_children():
		if child is Node3D:
			var enemy := child as Node3D
			if not placed.has(enemy):
				placed.append(enemy)
			enemy.set_meta("planning_actor_kind", "enemy")
			enemy.set_meta("planning_existing", true)


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
	var direct := _visual_object_at(screen_pos)
	if direct != null:
		return direct
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


func _visual_object_at(screen_pos: Vector2) -> Node3D:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_direction := camera.project_ray_normal(screen_pos)
	var best: Node3D
	var best_distance := INF
	for node in placed:
		if not is_instance_valid(node):
			continue
		var aabb := _combined_aabb(node)
		if aabb.size.length_squared() <= 0.0001:
			continue
		var world_aabb := node.global_transform * aabb
		var hit: Variant = world_aabb.intersects_ray(ray_origin, ray_direction)
		if hit == null:
			continue
		var hit_position: Vector3 = hit as Vector3
		var distance: float = ray_origin.distance_to(hit_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


func _rebuild_preview() -> void:
	_clear_preview()
	if _selected_kind() == "player":
		preview = _make_player_spawn_preview()
		host.add_child(preview)
		return
	if selected_path.is_empty():
		return
	var scene := load(selected_path) as PackedScene
	if scene == null:
		return
	preview = scene.instantiate() as Node3D
	host.add_child(preview)
	_set_preview_collision(preview, true)


func _selected_kind() -> String:
	for entry: Dictionary in active_catalog:
		if str(entry.get("path", "")) == selected_path and not selected_path.is_empty():
			return str(entry.get("kind", ""))
	if selected_path.is_empty() and active_catalog == actor_catalog:
		var selected_items := palette.get_selected_items()
		if not selected_items.is_empty():
			return str(actor_catalog[selected_items[0]].get("kind", ""))
	return ""


func _make_player_spawn_preview() -> Node3D:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.45
	mesh.height = 1.8
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.15, 0.55, 1.0, 0.45)
	mesh.material = material
	marker.mesh = mesh
	marker.set_meta("planning_spawn_preview", true)
	return marker


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
	var kind := _selected_kind()
	if kind == "player":
		main_player.global_position = _snap(world) + Vector3(0.0, 1.0, 0.0)
		main_player.rotation_degrees.y = rotation_y
		status.text = "Player spawn moved"
		_rebuild_preview()
		return
	if selected_path.is_empty():
		return
	var scene := load(selected_path) as PackedScene
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	var target_parent := enemies_root if kind == "enemy" else root
	target_parent.add_child(node)
	node.global_position = _snap_position_for(node, world)
	if kind == "enemy":
		node.global_position.y = 1.0
		node.set_meta("planning_actor_kind", "enemy")
		if node.has_method("set_target"):
			node.call("set_target", main_player)
	node.rotation_degrees.y = rotation_y
	node.set_meta("planning_scene_path", selected_path)
	placed.append(node)
	_select(null)
	_rebuild_preview()
	if preview != null:
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
	if node == main_player or str(node.get_meta("planning_actor_kind", "")) == "player":
		status.text = "Player spawn cannot be deleted; move it instead"
		return
	_clear_selection_highlight()
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


func _rotate_camera(relative: Vector2) -> void:
	planning_yaw -= relative.x * CAMERA_ROTATE_SPEED
	planning_pitch = clampf(planning_pitch - relative.y * CAMERA_ROTATE_SPEED, deg_to_rad(-80.0), deg_to_rad(-20.0))
	var current_position := camera.global_position
	camera.global_rotation = Vector3(planning_pitch, planning_yaw, 0.0)
	camera.global_position = current_position


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
	var source_sockets := _connection_sockets(node, base, source_aabb)
	var best := base
	var best_distance := SNAP_DISTANCE
	for other in placed:
		if other == node or not is_instance_valid(other):
			continue
		var other_aabb := _combined_aabb(other)
		if other_aabb.size.length_squared() <= 0.0001:
			continue
		var other_sockets := _connection_sockets(other, other.global_position, other_aabb)
		for source_socket: Vector3 in source_sockets:
			for target_socket: Vector3 in other_sockets:
				var distance := Vector2(source_socket.x - target_socket.x, source_socket.z - target_socket.z).length()
				if distance < best_distance:
					best_distance = distance
					best = base + (target_socket - source_socket)
					best.y = 0.0
	return best


func _connection_sockets(node: Node3D, world_origin: Vector3, aabb: AABB) -> Array[Vector3]:
	var center_local := Vector3(aabb.position.x + aabb.size.x * 0.5, 0.0, aabb.position.z + aabb.size.z * 0.5)
	var half_x := aabb.size.x * 0.5
	var half_z := aabb.size.z * 0.5
	var local_points: Array[Vector3] = [
		center_local + Vector3(-half_x, 0.0, 0.0),
		center_local + Vector3(half_x, 0.0, 0.0),
		center_local + Vector3(0.0, 0.0, -half_z),
		center_local + Vector3(0.0, 0.0, half_z)
	]
	var basis := Basis(Vector3.UP, node.rotation.y)
	var sockets: Array[Vector3] = []
	for point: Vector3 in local_points:
		var relative := point - Vector3(aabb.position.x + aabb.size.x * 0.5, 0.0, aabb.position.z + aabb.size.z * 0.5)
		sockets.append(world_origin + basis * relative)
	return sockets


func _combined_aabb(node: Node3D, ignore_selection: bool = false) -> AABB:
	var result := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if ignore_selection and child == selection_box:
			continue
		if child.has_meta("planning_selection_highlight"):
			continue
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
			"scene": scene_path,
			"x": node.position.x, "y": node.position.y, "z": node.position.z,
			"rotation_y": node.rotation_degrees.y,
			"scale_x": node.scale.x, "scale_y": node.scale.y, "scale_z": node.scale.z
		})
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version":3,"objects":objects}, "\t"))
	var scene_error := _save_authored_scene()
	if scene_error == OK:
		status.text = "SAVED | %d objects" % objects.size()
	else:
		status.text = "SAVE ERROR %d" % scene_error


func _save_authored_scene() -> Error:
	var scene_root := Node3D.new()
	scene_root.name = "BaseOfficeLayout"
	for node in placed:
		if not is_instance_valid(node):
			continue
		var scene_path := str(node.get_meta("planning_scene_path", ""))
		if scene_path.is_empty():
			continue
		var packed := load(scene_path) as PackedScene
		if packed == null:
			continue
		var copy := packed.instantiate() as Node3D
		if copy == null:
			continue
		scene_root.add_child(copy)
		copy.owner = scene_root
		copy.transform = node.transform
		_assign_owner_recursive(copy, scene_root)
	var packed_layout := PackedScene.new()
	var pack_error := packed_layout.pack(scene_root)
	if pack_error != OK:
		scene_root.free()
		return pack_error
	var save_error := ResourceSaver.save(packed_layout, AUTHORED_SCENE_PATH)
	scene_root.free()
	return save_error


func _assign_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		_assign_owner_recursive(child, scene_owner)


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
		var scene_path := _migrate_scene_path(str(record.get("scene", "")))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var scene := load(scene_path) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate() as Node3D
		root.add_child(node)
		node.position = Vector3(float(record.get("x",0.0)),float(record.get("y",0.0)),float(record.get("z",0.0)))
		node.rotation_degrees.y = float(record.get("rotation_y",0.0))
		node.scale = Vector3(float(record.get("scale_x",1.0)),float(record.get("scale_y",1.0)),float(record.get("scale_z",1.0)))
		node.set_meta("planning_scene_path", scene_path)
		placed.append(node)


func _migrate_scene_path(old_path: String) -> String:
	var replacements := {
		"res://models/objects/01_wall_door.glb": "res://game/presentation/office_floor/public/structural/wall_door.tscn",
		"res://models/objects/01_wall_door_2.glb": "res://game/presentation/office_floor/public/structural/wall_door.tscn",
		"res://models/objects/01_wall_inner_corner.blend": "",
		"res://game/presentation/office_floor/public/structural/wall_inner_corner.tscn": ""
	}
	if replacements.has(old_path):
		return str(replacements[old_path])
	return old_path


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
