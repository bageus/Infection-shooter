extends RefCounted

const GRID_SIZE = 0.25
const SNAP_DISTANCE = 0.8
const FLOOR_WALL_SNAP = preload("res://game/bootstrap/app/floor_wall_snap.gd")
const EXTINGUISHER_WALL = preload("res://game/bootstrap/app/extinguisher_wall_placement.gd")
const PLAN_HALF_WIDTH = 40.0
const PLAN_HALF_DEPTH = 30.0

var selection_box: MeshInstance3D
var selection_source_aabb = AABB()
var planning_grid: MeshInstance3D

var session: Variant
var objects: Variant


func configure(context: Dictionary) -> void:
	session = context["session"]
	objects = context["objects"]


func _show_selection_highlight(node: Node3D) -> void:
	var aabb = _combined_aabb(node, true)
	selection_source_aabb = aabb
	if aabb.size.length_squared() <= 0.0001:
		return
	selection_box = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = aabb.size + Vector3(0.08, 0.08, 0.08)
	var material = StandardMaterial3D.new()
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


func _show_planning_grid() -> void:
	if planning_grid != null and is_instance_valid(planning_grid):
		return
	planning_grid = MeshInstance3D.new()
	var mesh = ImmediateMesh.new()
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 0.75, 1.0, 0.38)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for x in range(-int(PLAN_HALF_WIDTH), int(PLAN_HALF_WIDTH) + 1):
		mesh.surface_add_vertex(Vector3(x, 0.012, -PLAN_HALF_DEPTH))
		mesh.surface_add_vertex(Vector3(x, 0.012, PLAN_HALF_DEPTH))
	for z in range(-int(PLAN_HALF_DEPTH), int(PLAN_HALF_DEPTH) + 1):
		mesh.surface_add_vertex(Vector3(-PLAN_HALF_WIDTH, 0.012, z))
		mesh.surface_add_vertex(Vector3(PLAN_HALF_WIDTH, 0.012, z))
	mesh.surface_end()
	var red = StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.cull_mode = BaseMaterial3D.CULL_DISABLED
	red.albedo_color = Color(1.0, 0.06, 0.06)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, red)
	_add_grid_rectangle(mesh, Vector3(-PLAN_HALF_WIDTH, 0.035, -0.045), Vector3(PLAN_HALF_WIDTH, 0.035, 0.045))
	_add_grid_rectangle(mesh, Vector3(-0.045, 0.035, -PLAN_HALF_DEPTH), Vector3(0.045, 0.035, PLAN_HALF_DEPTH))
	_add_grid_marker(mesh, Vector2.ZERO, 0.7)
	for x in [-PLAN_HALF_WIDTH * 0.5, PLAN_HALF_WIDTH * 0.5]:
		for z in [-PLAN_HALF_DEPTH * 0.5, PLAN_HALF_DEPTH * 0.5]:
			_add_grid_marker(mesh, Vector2(x, z), 0.5)
	mesh.surface_end()
	planning_grid.mesh = mesh
	session.host.add_child(planning_grid)


func _hide_planning_grid() -> void:
	if planning_grid != null and is_instance_valid(planning_grid):
		planning_grid.queue_free()
	planning_grid = null


func _add_grid_rectangle(mesh: ImmediateMesh, minimum: Vector3, maximum: Vector3) -> void:
	var a = Vector3(minimum.x, minimum.y, minimum.z)
	var b = Vector3(maximum.x, minimum.y, minimum.z)
	var c = Vector3(maximum.x, minimum.y, maximum.z)
	var d = Vector3(minimum.x, minimum.y, maximum.z)
	for vertex in [a, b, c, a, c, d]:
		mesh.surface_add_vertex(vertex)


func _add_grid_marker(mesh: ImmediateMesh, center: Vector2, radius: float) -> void:
	for sector in 16:
		var first = TAU * float(sector) / 16.0
		var second = TAU * float(sector + 1) / 16.0
		mesh.surface_add_vertex(Vector3(center.x, 0.045, center.y))
		mesh.surface_add_vertex(Vector3(center.x + cos(first) * radius, 0.045, center.y + sin(first) * radius))
		mesh.surface_add_vertex(Vector3(center.x + cos(second) * radius, 0.045, center.y + sin(second) * radius))


func _make_player_spawn_preview() -> Node3D:
	var marker = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.45
	mesh.height = 1.8
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.15, 0.55, 1.0, 0.45)
	mesh.material = material
	marker.mesh = mesh
	marker.set_meta("planning_spawn_preview", true)
	return marker


func _find_collision_descendant(node: Node) -> CollisionObject3D:
	if node is CollisionObject3D:
		return node as CollisionObject3D
	for child in node.get_children():
		var found = _find_collision_descendant(child)
		if found != null:
			return found
	return null


func _planned_object_at(screen_pos: Vector2) -> Node3D:
	var direct = _visual_object_at(screen_pos)
	if direct != null:
		return direct
	var origin = session.camera.project_ray_origin(screen_pos)
	var end = origin + session.camera.project_ray_normal(screen_pos) * 300.0
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var hit = session.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider = hit.get("collider") as Node
	if collider == null:
		return null
	return objects._editable_root_from_collider(collider)


func _visual_object_at(screen_pos: Vector2) -> Node3D:
	var ray_origin = session.camera.project_ray_origin(screen_pos)
	var ray_direction = session.camera.project_ray_normal(screen_pos)
	var best: Node3D
	var best_distance = INF
	for node in objects.placed:
		if not is_instance_valid(node):
			continue
		var aabb = _combined_aabb(node)
		if aabb.size.length_squared() <= 0.0001:
			continue
		var world_aabb = node.global_transform * aabb
		var hit: Variant = world_aabb.intersects_ray(ray_origin, ray_direction)
		if hit == null:
			continue
		var hit_position: Vector3 = hit as Vector3
		var distance: float = ray_origin.distance_to(hit_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


func _screen_to_surface(screen_pos: Vector2, placing: Node3D) -> Vector3:
	var origin = session.camera.project_ray_origin(screen_pos)
	var end = origin + session.camera.project_ray_normal(screen_pos) * 300.0
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	if placing != null and placing.has_meta("planning_preview"):
		query.exclude = []
	var hit = session.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var point: Vector3 = hit.get("position")
		var normal: Vector3 = hit.get("normal")
		if placing != null and bool(placing.get_meta("planning_wall_mount", false)) and absf(normal.y) < 0.35:
			point += normal * 0.025
			placing.set_meta("planning_wall_normal", normal)
			return point
		if placing != null and bool(placing.get_meta("planning_wall_mount", false)):
			if objects.selected_path.get_file() == "09_fire_extinguisher.glb" and normal.y > 0.55:
				var mounted = EXTINGUISHER_WALL.from_floor(placing, point)
				if mounted.is_finite():
					return mounted
			if placing.has_meta("planning_wall_normal"):
				placing.remove_meta("planning_wall_normal")
			return Vector3(INF, INF, INF)
		if normal.y > 0.55:
			return point
	if placing != null and bool(placing.get_meta("planning_wall_mount", false)):
		if placing.has_meta("planning_wall_normal"):
			placing.remove_meta("planning_wall_normal")
		return Vector3(INF, INF, INF)
	return _screen_to_floor(screen_pos)


func _screen_to_floor(screen_pos: Vector2) -> Vector3:
	var origin = session.camera.project_ray_origin(screen_pos)
	var direction = session.camera.project_ray_normal(screen_pos)
	if absf(direction.y) < 0.0001:
		return Vector3(INF, INF, INF)
	var distance = -origin.y / direction.y
	if distance < 0.0:
		return Vector3(INF, INF, INF)
	return origin + direction * distance


func _is_ceiling_tool(node: Node3D) -> bool:
	if node.is_in_group("planner_lights") or node.is_in_group("darkness_zone"):
		return true
	var kind = str(node.get_meta("planning_kind", ""))
	return kind == "light" or kind == "darkness" or kind == "exploration_darkness"


func _apply_wall_mount(node: Node3D) -> void:
	if not bool(node.get_meta("planning_wall_mount", false)):
		return
	if not node.has_meta("planning_wall_normal"):
		return
	var normal: Vector3 = node.get_meta("planning_wall_normal")
	var facing = atan2(normal.x, normal.z)
	node.rotation.y = facing


func _snap_position_for(node: Node3D, value: Vector3) -> Vector3:
	var base = _snap(value)
	var source_aabb = _combined_aabb(node)
	if bool(node.get_meta("planning_wall_mount", false)) and node.has_meta("planning_wall_normal"):
		return value
	else:
		var support_y = _support_height_at(node, base)
		if value.y > 0.01:
			support_y = maxf(support_y, value.y - source_aabb.position.y)
		base.y = support_y - source_aabb.position.y
	if source_aabb.size.length_squared() <= 0.0001:
		return base
	var source_sockets = _connection_sockets(node, base, source_aabb)
	var best = base
	var best_distance = SNAP_DISTANCE
	for other in objects.placed:
		if other == node or not is_instance_valid(other):
			continue
		var other_aabb = _combined_aabb(other)
		if other_aabb.size.length_squared() <= 0.0001:
			continue
		var other_sockets = _connection_sockets(other, other.global_position, other_aabb)
		for source_socket: Vector3 in source_sockets:
			for target_socket: Vector3 in other_sockets:
				var distance = Vector2(source_socket.x - target_socket.x, source_socket.z - target_socket.z).length()
				if distance < best_distance:
					best_distance = distance
					best = base + (target_socket - source_socket)
					best.y = base.y
	if node is RigidBody3D or bool(node.get_meta("planning_surface_placeable", false)):
		return FLOOR_WALL_SNAP.position_for(node, source_aabb, best)
	return best


func _support_height_at(node: Node3D, base: Vector3) -> float:
	var best_height = 0.0
	var node_aabb = _combined_aabb(node)
	var node_half = Vector2(node_aabb.size.x * 0.5, node_aabb.size.z * 0.5)
	for other in objects.placed:
		if other == node or not is_instance_valid(other):
			continue
		var scene_path = str(other.get_meta("planning_scene_path", ""))
		if not scene_path.ends_with("/floor_pad.tscn"):
			continue
		var pad_aabb = _combined_aabb(other)
		if pad_aabb.size.length_squared() <= 0.0001:
			continue
		var pad_world = other.global_transform * pad_aabb
		var center = pad_world.get_center()
		var half = Vector2(pad_world.size.x * 0.5, pad_world.size.z * 0.5)
		if absf(base.x - center.x) <= half.x + node_half.x * 0.25 and absf(base.z - center.z) <= half.y + node_half.y * 0.25:
			best_height = maxf(best_height, pad_world.position.y + pad_world.size.y)
	return best_height


func _connection_sockets(node: Node3D, world_origin: Vector3, aabb: AABB) -> Array[Vector3]:
	var center_local = Vector3(aabb.position.x + aabb.size.x * 0.5, 0.0, aabb.position.z + aabb.size.z * 0.5)
	var half_x = aabb.size.x * 0.5
	var half_z = aabb.size.z * 0.5
	var local_points: Array[Vector3] = [
		center_local + Vector3(-half_x, 0.0, 0.0),
		center_local + Vector3(half_x, 0.0, 0.0),
		center_local + Vector3(0.0, 0.0, -half_z),
		center_local + Vector3(0.0, 0.0, half_z)
	]
	var basis = Basis(Vector3.UP, node.rotation.y)
	var sockets: Array[Vector3] = []
	for point: Vector3 in local_points:
		var relative = point - Vector3(aabb.position.x + aabb.size.x * 0.5, 0.0, aabb.position.z + aabb.size.z * 0.5)
		sockets.append(world_origin + basis * relative)
	return sockets


func _combined_aabb(node: Node3D, ignore_selection: bool = false) -> AABB:
	var result = AABB()
	var found = false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if ignore_selection and child == selection_box:
			continue
		if child.has_meta("planning_selection_highlight"):
			continue
		var mesh_instance = child as MeshInstance3D
		if mesh_instance != null and mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue # Shadow proxies are not visible placement geometry.
		if mesh_instance == null or mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree() or absf(mesh_instance.global_basis.determinant()) < 0.000000000001:
			continue
		var local_transform = node.global_transform.affine_inverse() * mesh_instance.global_transform
		var aabb = local_transform * mesh_instance.get_aabb()
		if not found:
			result = aabb
			found = true
		else:
			result = result.merge(aabb)
	return result


func _snap(value: Vector3) -> Vector3:
	return Vector3(roundf(value.x / GRID_SIZE) * GRID_SIZE, 0.0, roundf(value.z / GRID_SIZE) * GRID_SIZE)


func _set_preview_collision(node: Node, disabled: bool) -> void:
	if disabled and node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = disabled
	for child in node.get_children():
		_set_preview_collision(child, disabled)
