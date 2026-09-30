extends RefCounted

# Apply placement, selection picking and object edit commands.
var planner: Variant


func _init(context: Node) -> void:
	planner = context


func _click_world(screen_pos: Vector2) -> void:
	if not planner.selected_path.is_empty() or planner.selected_kind == "player":
		_place_selected(screen_pos)
		return
	var hit_node = _planned_object_at(screen_pos)
	planner.view._select(hit_node)
	if hit_node != null:
		_clear_preview()


func _register_existing_scene_objects() -> void:
	_register_editable_children(planner.structure_root)


func _register_editable_children(parent: Node) -> void:
	for child in parent.get_children():
		if child is Node3D:
			var node = child as Node3D
			if _is_editable_scene_object(node):
				if not planner.placed.has(node):
					planner.placed.append(node)
				node.set_meta("planning_existing", true)
			else:
				_register_editable_children(node)


func _activate_all_enemies() -> void:
	for child in planner.enemies_root.get_children():
		if child.has_method("set_target"):
			child.call("set_target", planner.main_player)


func _register_actor_objects() -> void:
	if planner.main_player != null and not planner.placed.has(planner.main_player):
		planner.placed.append(planner.main_player)
		planner.main_player.set_meta("planning_actor_kind", "player")
		planner.main_player.set_meta("planning_existing", true)
	for child in planner.enemies_root.get_children():
		if child is Node3D:
			var enemy = child as Node3D
			if not planner.placed.has(enemy):
				planner.placed.append(enemy)
			enemy.set_meta("planning_actor_kind", "enemy")
			enemy.set_meta("planning_existing", true)


func _is_editable_scene_object(node: Node3D) -> bool:
	if node == planner.root or node == planner.structure_root:
		return false
	return _find_collision_descendant(node) != null and node.get_parent() != planner.host


func _find_collision_descendant(node: Node) -> CollisionObject3D:
	if node is CollisionObject3D:
		return node as CollisionObject3D
	for child in node.get_children():
		var found = _find_collision_descendant(child)
		if found != null:
			return found
	return null


func _editable_root_from_collider(collider: Node) -> Node3D:
	var node: Node = collider
	while node != null:
		if node.get_parent() == planner.root:
			return node as Node3D
		if node is Node3D and planner.placed.has(node):
			return node as Node3D
		if node.get_parent() == planner.structure_root:
			return node as Node3D
		node = node.get_parent()
	return null


func _planned_object_at(screen_pos: Vector2) -> Node3D:
	var direct = _visual_object_at(screen_pos)
	if direct != null:
		return direct
	var origin = planner.camera.project_ray_origin(screen_pos)
	var end = origin + planner.camera.project_ray_normal(screen_pos) * 300.0
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var hit = planner.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider = hit.get("collider") as Node
	if collider == null:
		return null
	return _editable_root_from_collider(collider)


func _visual_object_at(screen_pos: Vector2) -> Node3D:
	var ray_origin = planner.camera.project_ray_origin(screen_pos)
	var ray_direction = planner.camera.project_ray_normal(screen_pos)
	var best: Node3D
	var best_distance = INF
	for node in planner.placed:
		if not is_instance_valid(node):
			continue
		var aabb = planner.geometry._combined_aabb(node)
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


func _rebuild_preview() -> void:
	_clear_preview()
	if _selected_kind() == "player":
		planner.preview = _make_player_spawn_preview()
		planner.host.add_child(planner.preview)
		return
	if planner.selected_path.is_empty():
		return
	planner.preview = planner.catalog._instantiate_asset(planner.selected_path)
	if planner.preview == null:
		return
	planner.host.add_child(planner.preview)
	if _selected_kind() == "light" and planner.preview.has_method("set_planning_visual"):
		planner.preview.call_deferred("set_planning_visual", true)
	_set_preview_collision(planner.preview, true)
	planner.geometry._apply_special_default_height(planner.preview, _selected_kind())


func _selected_kind() -> String:
	return planner.selected_kind


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


func _clear_preview() -> void:
	planner.light_info.hide()
	planner.light_level.hide()
	planner.light_angle_info.hide()
	planner.light_angle.hide()
	planner.ui.get_node("Panel/VBox/SelectedFlicker").hide()
	planner.ui.get_node("Panel/VBox/SelectedFlickerStep").hide()
	if planner.preview != null and is_instance_valid(planner.preview):
		planner.preview.queue_free()
	planner.preview = null


func _update_preview(screen_pos: Vector2) -> void:
	if planner.preview == null:
		return
	var world = planner.geometry._screen_to_surface(screen_pos, planner.preview)
	if not world.is_finite():
		planner.preview.hide()
		return
	planner.preview.show()
	planner.preview.global_position = planner.geometry._snap_position_for(planner.preview, world)
	planner.geometry._apply_special_default_height(planner.preview, _selected_kind())
	planner.preview.rotation_degrees.y = planner.rotation_y
	planner.geometry._apply_wall_mount(planner.preview)
	planner.view._update_light_ui()


func _place_selected(screen_pos: Vector2) -> void:
	var placement_probe = planner.preview
	var world = planner.geometry._screen_to_surface(screen_pos, placement_probe)
	if not world.is_finite():
		if placement_probe != null and bool(placement_probe.get_meta("planning_wall_mount", false)):
			planner.status.text = "Aim at a wall to place this wall-mounted object."
		return
	var kind = _selected_kind()
	if kind == "player":
		planner.edit_history.call("record_player_spawn")
		planner.main_player.global_position = planner.geometry._snap(world) + Vector3(0.0, 1.0, 0.0)
		planner.main_player.rotation_degrees.y = planner.rotation_y
		planner.player_spawn_defined = true
		planner.player_spawn_transform = planner.main_player.transform
		planner.main_player.set_meta("planning_scene_path", "res://game/features/player/public/player.tscn")
		planner.status.text = "Player spawn set"
		_rebuild_preview()
		return
	if planner.selected_path.is_empty():
		return
	var node = planner.catalog._instantiate_asset(planner.selected_path)
	if node == null:
		return
	if kind == "exploration_darkness":
		node.set("permanent", false)
		node.set_meta("planning_permanent", false)
	elif kind == "darkness":
		node.set("permanent", true)
		node.set_meta("planning_permanent", true)
	var target_parent = planner.enemies_root if kind == "enemy" else planner.root
	target_parent.add_child(node)
	if planner.preview != null and planner.preview.has_meta("planning_wall_normal"):
		node.set_meta("planning_wall_normal", planner.preview.get_meta("planning_wall_normal"))
	if bool(node.get_meta("planning_wall_mount", false)) and not node.has_meta("planning_wall_normal"):
		planner.status.text = "Aim at a wall to place this wall-mounted object."
		node.queue_free()
		return
	node.global_position = planner.geometry._snap_position_for(node, world)
	planner.geometry._apply_special_default_height(node, kind)
	if kind == "enemy":
		node.global_position.y = 1.0
		node.set_meta("planning_actor_kind", "enemy")
		if node.has_method("set_target"):
			node.call("set_target", planner.main_player)
	node.rotation_degrees.y = planner.rotation_y
	planner.geometry._apply_wall_mount(node)
	if planner.selected_path.get_file() == "06_conference_chair.glb":
		planner.geometry._ground_conference_chair(node)
	node.set_meta("planning_scene_path", planner.selected_path)
	planner.placed.append(node)
	planner.edit_history.call("record_added", node)
	if not planner.WORKSTATIONS.desk_name(planner.selected_path).is_empty():
		var desk_id = str(Time.get_ticks_usec())
		node.set_meta("planning_desk_id", desk_id)
		var objects: Array[Node3D] = planner.WORKSTATIONS.from_saved_template(node, planner.selected_path, planner.root, Callable(planner, "_instantiate_asset"))
		for object in objects:
			object.set_meta("planning_attachment", desk_id)
			planner.placed.append(object)
		planner.workstation_transforms[desk_id] = node.global_transform
	if kind == "light" and node.has_method("set_planning_visual"):
		node.call("set_planning_visual", true)
	planner.view._select(null)
	_rebuild_preview()
	if planner.preview != null:
		_update_preview(screen_pos)
	planner.status.text = "Placed | same object remains active | RMB cancel"


func _delete_at(screen_pos: Vector2) -> void:
	var node = _planned_object_at(screen_pos)
	if node != null:
		_delete_node(node)


func _delete_selected() -> void:
	if planner.selected != null:
		planner.edit_history.call("record_deleted", planner.selected)
		_delete_node(planner.selected)


func _delete_node(node: Node3D) -> void:
	if node == planner.main_player or str(node.get_meta("planning_actor_kind", "")) == "player":
		planner.status.text = "Player spawn cannot be deleted; move it instead"
		return
	planner.view._clear_selection_highlight()
	var desk_id = str(node.get_meta("planning_desk_id", ""))
	if not desk_id.is_empty():
		for object in planner.placed.duplicate():
			if is_instance_valid(object) and str(object.get_meta("planning_attachment", "")) == desk_id:
				planner.placed.erase(object)
				object.queue_free()
		planner.workstation_transforms.erase(desk_id)
	planner.placed.erase(node)
	if planner.selected == node:
		planner.selected = null
	node.queue_free()
	planner.view._update_status()
	planner.view._update_history_buttons()


func _sync_workstations() -> void:
	for desk in planner.placed:
		if not is_instance_valid(desk):
			continue
		var desk_id = str(desk.get_meta("planning_desk_id", ""))
		if desk_id.is_empty():
			continue
		if not planner.workstation_transforms.has(desk_id):
			planner.workstation_transforms[desk_id] = desk.global_transform
			continue
		var previous: Transform3D = planner.workstation_transforms[desk_id]
		if previous.is_equal_approx(desk.global_transform):
			continue
		var difference = desk.global_transform * previous.affine_inverse()
		for object in planner.placed:
			if is_instance_valid(object) and str(object.get_meta("planning_attachment", "")) == desk_id:
				object.global_transform = difference * object.global_transform
		planner.workstation_transforms[desk_id] = desk.global_transform


func _rotate_selected(amount: float) -> void:
	if planner.selected != null:
		planner.edit_history.call("record_transform", planner.selected)
		planner.selected.rotation_degrees.y = fmod(planner.selected.rotation_degrees.y + amount + 360.0, 360.0)
	elif planner.preview != null:
		planner.rotation_y = fmod(planner.rotation_y + amount + 360.0, 360.0)
		planner.preview.rotation_degrees.y = planner.rotation_y
	planner.view._update_status()


func _scale_selected(delta_scale: Vector3) -> void:
	if planner.selected == null:
		return
	planner.edit_history.call("record_transform", planner.selected)
	var next = planner.selected.scale + delta_scale
	next.x = maxf(next.x, 0.1)
	next.y = maxf(next.y, 0.1)
	next.z = maxf(next.z, 0.1)
	planner.selected.scale = next
	planner.view._update_status()


func _nudge_selected(input: Vector2) -> void:
	if planner.selected == null:
		return
	planner.edit_history.call("record_transform", planner.selected)
	var forward = -planner.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right = planner.camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var motion = (right * input.x + forward * -input.y) * planner.GRID_SIZE
	planner.selected.global_position += motion
	planner.selected.global_position.x = roundf(planner.selected.global_position.x / planner.GRID_SIZE) * planner.GRID_SIZE
	planner.selected.global_position.z = roundf(planner.selected.global_position.z / planner.GRID_SIZE) * planner.GRID_SIZE
	planner.view._update_status()


func _adjust_selected_light_angle(amount: float) -> void:
	if planner.selected == null:
		return
	var light = planner.selected.find_child("Light", true, false) as SpotLight3D
	if light == null:
		return
	planner.edit_history.call("record_transform", planner.selected)
	light.spot_angle = clampf(light.spot_angle + amount, 5.0, 89.0)
	planner.selected.set_meta("planning_light_angle", light.spot_angle)
	planner.view._update_light_ui()
	planner.status.text = "LIGHT | cone %.0f° | , / . adjust" % light.spot_angle


func _adjust_selected_light(amount: float) -> void:
	if planner.selected == null:
		return
	var light = planner.selected.find_child("Light", true, false) as Light3D
	if light == null:
		return
	planner.edit_history.call("record_transform", planner.selected)
	planner.selected.call("set_authored_energy", clampf(float(planner.selected.call("get_authored_energy")) + amount, 0.0, 16.0))
	planner.view._update_light_ui()
	planner.status.text = "LIGHT | brightness %.2f | [ / ] adjust" % float(planner.selected.call("get_authored_energy"))


func _move_selected_height(amount: float) -> void:
	if planner.selected != null:
		planner.edit_history.call("record_transform", planner.selected)
		planner.selected.position.y += amount
		planner.view._update_status()
	elif planner.preview != null:
		planner.preview.position.y += amount


func clear_layout(update_status: bool = true) -> void:
	planner.workstation_transforms.clear()
	var retained: Array[Node3D] = []
	for node in planner.placed:
		if not is_instance_valid(node):
			continue
		if bool(node.get_meta("planning_existing", false)):
			retained.append(node)
		else:
			node.queue_free()
	planner.placed = retained
	planner.selected = null
	if update_status:
		planner.view._update_status()


func _set_preview_collision(node: Node, disabled: bool) -> void:
	if disabled and node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = disabled
	for child in node.get_children():
		_set_preview_collision(child, disabled)
