extends RefCounted

# Calculate planner camera rays, snapping and support geometry.
var planner: Variant


func _init(context: Node) -> void:
	planner = context


func _rotate_camera(relative: Vector2) -> void:
	planner.planning_yaw -= relative.x * planner.CAMERA_ROTATE_SPEED
	planner.planning_pitch = clampf(planner.planning_pitch - relative.y * planner.CAMERA_ROTATE_SPEED, deg_to_rad(-80.0), deg_to_rad(80.0))
	var current_position = planner.camera.global_position
	planner.camera.global_rotation = Vector3(planner.planning_pitch, planner.planning_yaw, 0.0)
	planner.camera.global_position = current_position


func _zoom_camera(amount: float) -> void:
	planner.camera_height = clampf(planner.camera_height + amount, planner.CAMERA_MIN_HEIGHT, planner.CAMERA_MAX_HEIGHT)
	var p = planner.camera.global_position
	p.y = planner.camera_height
	planner.camera.global_position = p


func _screen_to_surface(screen_pos: Vector2, placing: Node3D) -> Vector3:
	var origin = planner.camera.project_ray_origin(screen_pos)
	var end = origin + planner.camera.project_ray_normal(screen_pos) * 300.0
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	if placing != null and placing.has_meta("planning_preview"):
		query.exclude = []
	var hit = planner.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var point: Vector3 = hit.get("position")
		var normal: Vector3 = hit.get("normal")
		if placing != null and bool(placing.get_meta("planning_wall_mount", false)) and absf(normal.y) < 0.35:
			point += normal * 0.025
			placing.set_meta("planning_wall_normal", normal)
			return point
		if placing != null and bool(placing.get_meta("planning_wall_mount", false)):
			if planner.selected_path.get_file() == "09_fire_extinguisher.glb" and normal.y > 0.55:
				var mounted = planner.EXTINGUISHER_WALL.from_floor(placing, point)
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
	var origin = planner.camera.project_ray_origin(screen_pos)
	var direction = planner.camera.project_ray_normal(screen_pos)
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


func _apply_special_default_height(node: Node3D, kind: String) -> void:
	if kind == "light":
		node.global_position.y = float(planner.default_light_height.value) if planner.default_light_height != null else planner.LIGHT_DEFAULT_HEIGHT
		_apply_new_light_defaults(node)
	elif kind == "darkness" or kind == "exploration_darkness":
		node.global_position.y = planner.DARKNESS_DEFAULT_HEIGHT


func _apply_new_light_defaults(node: Node3D) -> void:
	var spot = node.find_child("Light", true, false) as SpotLight3D
	if spot == null:
		return
	var energy = float(planner.default_light_energy.value) if planner.default_light_energy != null else 3.0
	var angle = float(planner.default_light_angle.value) if planner.default_light_angle != null else 48.0
	node.call("set_authored_energy", energy)
	spot.spot_angle = angle
	node.set_meta("planning_light_angle", angle)
	if node.has_method("configure_flicker"):
		node.call("configure_flicker", planner.default_flicker_mode.get_selected_id(), planner.default_flicker_step.value)


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
	var best_distance = planner.SNAP_DISTANCE
	for other in planner.placed:
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
		return planner.FLOOR_WALL_SNAP.position_for(node, source_aabb, best)
	return best


func _support_height_at(node: Node3D, base: Vector3) -> float:
	var best_height = 0.0
	var node_aabb = _combined_aabb(node)
	var node_half = Vector2(node_aabb.size.x * 0.5, node_aabb.size.z * 0.5)
	for other in planner.placed:
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
		if ignore_selection and child == planner.selection_box:
			continue
		if child.has_meta("planning_selection_highlight"):
			continue
		var mesh_instance = child as MeshInstance3D
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


func _ground_conference_chair(node: Node3D) -> void:
	var bounds = _combined_aabb(node)
	if bounds.size.length_squared() > 0.0001 and node.global_position.y < 0.25:
		node.global_position.y = maxf(node.global_position.y, 0.025 - bounds.position.y)


func _snap(value: Vector3) -> Vector3:
	return Vector3(roundf(value.x / planner.GRID_SIZE) * planner.GRID_SIZE, 0.0, roundf(value.z / planner.GRID_SIZE) * planner.GRID_SIZE)
