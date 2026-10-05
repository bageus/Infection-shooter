extends Node


var player_spawn_defined = false
var player_spawn_transform = Transform3D.IDENTITY
var selected_path = ""
var selected_kind = ""
var selected_entry: Dictionary = {}
var preview: Node3D
var selected: Node3D
var rotation_y = 0.0
var last_mouse_world = Vector3.ZERO
var placed: Array[Node3D] = []
var workstation_transforms: Dictionary = {}

var session: Variant
var geometry: Variant
var controls: Variant
var catalog: Variant


func configure(context: Dictionary) -> void:
	session = context["session"]
	geometry = context["geometry"]
	controls = context["controls"]
	catalog = context["catalog"]


func _on_palette_selected(index: int) -> void:
	var entry: Dictionary = catalog.active_catalog[index]
	selected_path = str(entry.get("path", ""))
	selected_kind = str(entry.get("kind", ""))
	selected_entry = entry
	rotation_y = 0.0
	_select(null)
	_rebuild_preview()


func _click_world(screen_pos: Vector2) -> void:
	if not selected_path.is_empty() or selected_kind == "player":
		_place_selected(screen_pos)
		return
	var hit_node = geometry._planned_object_at(screen_pos)
	_select(hit_node)
	if hit_node != null:
		_clear_preview()


func _select(node: Node3D) -> void:
	geometry._clear_selection_highlight()
	selected = node
	controls.desk_setup_button.visible = selected != null and not catalog.WORKSTATIONS.desk_name(str(selected.get_meta("planning_scene_path", ""))).is_empty()
	if selected != null:
		geometry._show_selection_highlight(selected)
	controls._update_light_ui()
	_update_status()
	controls._update_history_buttons()


func _reset_selection() -> void:
	selected_path = ""
	selected_kind = ""
	selected_entry = {}
	rotation_y = 0.0
	_clear_preview()
	_select(null)
	controls.palette.deselect_all()
	controls.status.text = "Selection cleared"


func _register_existing_scene_objects() -> void:
	_register_editable_children(session.structure_root)


func _register_editable_children(parent: Node) -> void:
	for child in parent.get_children():
		if child is Node3D:
			var node = child as Node3D
			if _is_editable_scene_object(node):
				if not placed.has(node):
					placed.append(node)
				node.set_meta("planning_existing", true)
			else:
				_register_editable_children(node)


func _activate_all_enemies() -> void:
	for child in session.enemies_root.get_children():
		if child.has_method("set_target"):
			child.call("set_target", session.main_player)


func _register_actor_objects() -> void:
	if session.main_player != null and not placed.has(session.main_player):
		placed.append(session.main_player)
		session.main_player.set_meta("planning_actor_kind", "player")
		session.main_player.set_meta("planning_existing", true)
	for child in session.enemies_root.get_children():
		if child is Node3D:
			var enemy = child as Node3D
			if not placed.has(enemy):
				placed.append(enemy)
			enemy.set_meta("planning_actor_kind", "enemy")
			enemy.set_meta("planning_existing", true)


func _is_editable_scene_object(node: Node3D) -> bool:
	if node == session.root or node == session.structure_root:
		return false
	return geometry._find_collision_descendant(node) != null and node.get_parent() != session.host


func _editable_root_from_collider(collider: Node) -> Node3D:
	var node: Node = collider
	while node != null:
		if node.get_parent() == session.root:
			return node as Node3D
		if node is Node3D and placed.has(node):
			return node as Node3D
		if node.get_parent() == session.structure_root:
			return node as Node3D
		node = node.get_parent()
	return null


func _rebuild_preview() -> void:
	_clear_preview()
	if _selected_kind() == "player":
		preview = geometry._make_player_spawn_preview()
		session.host.add_child(preview)
		return
	if selected_path.is_empty():
		return
	preview = catalog._instantiate_asset(selected_path)
	if preview == null:
		return
	controls._configure_new_asset(preview, selected_entry)
	session.host.add_child(preview)
	if _selected_kind() == "light" and preview.has_method("set_planning_visual"):
		preview.call_deferred("set_planning_visual", true)
	geometry._set_preview_collision(preview, true)
	controls._apply_special_default_height(preview, _selected_kind())


func _selected_kind() -> String:
	return selected_kind


func _clear_preview() -> void:
	session.ui.get_node("Panel/VBox/SelectedLightColor").hide()
	controls.light_info.hide()
	controls.light_level.hide()
	controls.light_angle_info.hide()
	controls.light_angle.hide()
	session.ui.get_node("Panel/VBox/SelectedFlicker").hide()
	session.ui.get_node("Panel/VBox/SelectedFlickerStep").hide()
	if preview != null and is_instance_valid(preview):
		preview.queue_free()
	preview = null


func _update_preview(screen_pos: Vector2) -> void:
	if preview == null:
		return
	var world = geometry._screen_to_surface(screen_pos, preview)
	if not world.is_finite():
		preview.hide()
		return
	preview.show()
	preview.global_position = geometry._snap_position_for(preview, world)
	controls._apply_special_default_height(preview, _selected_kind())
	preview.rotation_degrees.y = rotation_y
	geometry._apply_wall_mount(preview)
	controls._update_light_ui()


func _place_selected(screen_pos: Vector2) -> void:
	var placement_probe = preview
	var world = geometry._screen_to_surface(screen_pos, placement_probe)
	if not world.is_finite():
		if placement_probe != null and bool(placement_probe.get_meta("planning_wall_mount", false)):
			controls.status.text = "Aim at a wall to place this wall-mounted object."
		return
	var kind = _selected_kind()
	if kind == "player":
		session.edit_history.call("record_player_spawn")
		session.main_player.global_position = geometry._snap(world) + Vector3(0.0, 1.0, 0.0)
		session.main_player.rotation_degrees.y = rotation_y
		player_spawn_defined = true
		player_spawn_transform = session.main_player.transform
		session.main_player.set_meta("planning_scene_path", "res://game/features/player/public/player.tscn")
		controls.status.text = "Player spawn set"
		_rebuild_preview()
		return
	if selected_path.is_empty():
		return
	var node = catalog._instantiate_asset(selected_path)
	if node == null:
		return
	if kind == "exploration_darkness":
		node.set("permanent", false)
		node.set_meta("planning_permanent", false)
	elif kind == "darkness":
		node.set("permanent", true)
		node.set_meta("planning_permanent", true)
	controls._configure_new_asset(node, selected_entry)
	var target_parent = session.enemies_root if kind == "enemy" else session.root
	target_parent.add_child(node)
	if preview != null and preview.has_meta("planning_wall_normal"):
		node.set_meta("planning_wall_normal", preview.get_meta("planning_wall_normal"))
	if bool(node.get_meta("planning_wall_mount", false)) and not node.has_meta("planning_wall_normal"):
		controls.status.text = "Aim at a wall to place this wall-mounted object."
		node.queue_free()
		return
	node.global_position = geometry._snap_position_for(node, world)
	controls._apply_special_default_height(node, kind)
	if kind == "enemy":
		node.global_position.y = _enemy_spawn_height(node)
		node.set_meta("planning_actor_kind", "enemy")
		if node.has_method("set_target"):
			node.call("set_target", session.main_player)
	node.rotation_degrees.y = rotation_y
	geometry._apply_wall_mount(node)
	if selected_path.get_file() == "06_conference_chair.glb":
		_ground_conference_chair(node)
	node.set_meta("planning_scene_path", selected_path)
	placed.append(node)
	session.edit_history.call("record_added", node)
	if not catalog.WORKSTATIONS.desk_name(selected_path).is_empty():
		var desk_id = str(Time.get_ticks_usec())
		node.set_meta("planning_desk_id", desk_id)
		var attachments: Array[Node3D] = catalog.WORKSTATIONS.from_saved_template(node, selected_path, session.root, Callable(catalog, "_instantiate_asset"))
		for object in attachments:
			object.set_meta("planning_attachment", desk_id)
			placed.append(object)
		workstation_transforms[desk_id] = node.global_transform
	if kind == "light" and node.has_method("set_planning_visual"):
		node.call("set_planning_visual", true)
	_select(null)
	_rebuild_preview()
	if preview != null:
		_update_preview(screen_pos)
	controls.status.text = "Placed | same object remains active | RMB cancel"


func _delete_at(screen_pos: Vector2) -> void:
	var node = geometry._planned_object_at(screen_pos)
	if node != null:
		_delete_node(node)


func _delete_selected() -> void:
	if selected != null:
		session.edit_history.call("record_deleted", selected)
		_delete_node(selected)


func _delete_node(node: Node3D) -> void:
	if node == session.main_player or str(node.get_meta("planning_actor_kind", "")) == "player":
		controls.status.text = "Player spawn cannot be deleted; move it instead"
		return
	geometry._clear_selection_highlight()
	var desk_id = str(node.get_meta("planning_desk_id", ""))
	if not desk_id.is_empty():
		for object in placed.duplicate():
			if is_instance_valid(object) and str(object.get_meta("planning_attachment", "")) == desk_id:
				placed.erase(object)
				object.queue_free()
		workstation_transforms.erase(desk_id)
	placed.erase(node)
	if selected == node:
		selected = null
	node.queue_free()
	_update_status()
	controls._update_history_buttons()


func _sync_workstations() -> void:
	for desk in placed:
		if not is_instance_valid(desk):
			continue
		var desk_id = str(desk.get_meta("planning_desk_id", ""))
		if desk_id.is_empty():
			continue
		if not workstation_transforms.has(desk_id):
			workstation_transforms[desk_id] = desk.global_transform
			continue
		var previous: Transform3D = workstation_transforms[desk_id]
		if previous.is_equal_approx(desk.global_transform):
			continue
		var difference = desk.global_transform * previous.affine_inverse()
		for object in placed:
			if is_instance_valid(object) and str(object.get_meta("planning_attachment", "")) == desk_id:
				object.global_transform = difference * object.global_transform
		workstation_transforms[desk_id] = desk.global_transform


func _rotate_selected(amount: float) -> void:
	if selected != null:
		session.edit_history.call("record_transform", selected)
		selected.rotation_degrees.y = fmod(selected.rotation_degrees.y + amount + 360.0, 360.0)
	elif preview != null:
		rotation_y = fmod(rotation_y + amount + 360.0, 360.0)
		preview.rotation_degrees.y = rotation_y
	_update_status()


func _scale_selected(delta_scale: Vector3) -> void:
	if selected == null:
		return
	session.edit_history.call("record_transform", selected)
	var next = selected.scale + delta_scale
	next.x = maxf(next.x, 0.1)
	next.y = maxf(next.y, 0.1)
	next.z = maxf(next.z, 0.1)
	selected.scale = next
	_update_status()


func _nudge_selected(input: Vector2) -> void:
	if selected == null:
		return
	session.edit_history.call("record_transform", selected)
	var forward = -session.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right = session.camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var motion = (right * input.x + forward * -input.y) * geometry.GRID_SIZE
	selected.global_position += motion
	selected.global_position.x = roundf(selected.global_position.x / geometry.GRID_SIZE) * geometry.GRID_SIZE
	selected.global_position.z = roundf(selected.global_position.z / geometry.GRID_SIZE) * geometry.GRID_SIZE
	_update_status()


func _move_selected_height(amount: float) -> void:
	if selected != null:
		session.edit_history.call("record_transform", selected)
		selected.position.y += amount
		_update_status()
	elif preview != null:
		preview.position.y += amount


func _ground_conference_chair(node: Node3D) -> void:
	var bounds = geometry._combined_aabb(node)
	if bounds.size.length_squared() > 0.0001 and node.global_position.y < 0.25:
		node.global_position.y = maxf(node.global_position.y, 0.025 - bounds.position.y)


func _update_status() -> void:
	if selected == null:
		controls.status.text = "%d objects | select palette or object" % placed.size()
		return
	if selected.is_in_group("darkness_zone"):
		controls.status.text = "DARKNESS | scale X/Z changes covered area | Delete removes"
		return
	controls.status.text = "SELECTED | pos %.1f %.1f | rot %.0f | scale %.2f %.2f %.2f" % [
		selected.position.x, selected.position.z, selected.rotation_degrees.y,
		selected.scale.x, selected.scale.y, selected.scale.z
	]


## Rebuilds the layout from saved data; returns {"loaded", "skipped"}.
func _apply_layout_data(data: Dictionary) -> Dictionary:
	clear_layout(false)
	# Undo entries refer to the previous layout's objects.
	session.edit_history.set("stack", [])
	var loaded := 0
	var skipped := 0
	var records: Array = data.get("objects", [])
	var player_records: Array = []
	for record_value: Variant in records:
		if record_value is Dictionary:
			var candidate: Dictionary = record_value
			var candidate_path = str(candidate.get("scene", ""))
			if candidate_path == "res://game/features/player/public/player.tscn":
				player_records.append(candidate)
	if not player_records.is_empty():
		player_spawn_defined = true
		var latest: Dictionary = player_records[player_records.size() - 1]
		session.main_player.position = Vector3(float(latest.get("x",0.0)),float(latest.get("y",1.0)),float(latest.get("z",0.0)))
		session.main_player.rotation_degrees.y = float(latest.get("rotation_y",0.0))
		player_spawn_transform = session.main_player.transform
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var scene_path = catalog._migrate_scene_path(str(record.get("scene", "")))
		if scene_path == "res://game/features/player/public/player.tscn":
			continue
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			skipped += 1
			continue
		var node = catalog._instantiate_asset(scene_path)
		if node == null:
			skipped += 1
			continue
		if node.has_method("configure_blood") and record.has("blood_texture"):
			node.call("configure_blood", str(record["blood_texture"]), str(record.get("blood_surface", "floor")))
		var load_kind = "enemy" if scene_path in catalog.ENEMY_SCENES else ""
		var target_parent = session.enemies_root if load_kind == "enemy" else session.root
		target_parent.add_child(node)
		node.position = Vector3(float(record.get("x",0.0)),float(record.get("y",0.0)),float(record.get("z",0.0)))
		node.rotation_degrees.y = float(record.get("rotation_y",0.0))
		node.scale = Vector3(float(record.get("scale_x",1.0)),float(record.get("scale_y",1.0)),float(record.get("scale_z",1.0)))
		if scene_path.get_file() == "06_conference_chair.glb":
			_ground_conference_chair(node)
		node.set_meta("planning_scene_path", scene_path)
		if record.has("desk_id"):
			node.set_meta("planning_desk_id", str(record["desk_id"]))
		if record.has("attachment"):
			node.set_meta("planning_attachment", str(record["attachment"]))
		if int(record.get("zone", -1)) >= 0:
			node.set_meta("planning_zone", int(record["zone"]))
		if node.has_method("set_authored_energy"):
			node.set("energy_multiplier", float(record.get("energy_multiplier", 0.65)))
			node.call("set_authored_energy", float(record.get("light_energy", node.call("get_authored_energy"))))
		if node.has_method("set_authored_color"):
			var channels: Variant = record.get("light_color", [])
			if channels is Array and channels.size() >= 3:
				node.call("set_authored_color", Color(float(channels[0]), float(channels[1]), float(channels[2]), 1.0))
		var saved_light_angle = float(record.get("light_angle", 48.0))
		var saved_spot = node.find_child("Light", true, false) as SpotLight3D
		if saved_spot != null:
			saved_spot.spot_angle = saved_light_angle
			node.set_meta("planning_light_angle", saved_light_angle)
		if node.has_method("configure_flicker"):
			node.call("configure_flicker", int(record.get("flicker_mode", 0)), float(record.get("flicker_step", 0.2)))
		if node.get("darkness") != null:
			node.set("darkness", float(record.get("darkness", 0.88)))
			node.set("permanent", bool(record.get("permanent_darkness", true)))
			if node.has_method("configure_zone"):
				# The restored node scale already stretches the 4 m base zone.
				node.call("configure_zone", Vector2(4.0, 4.0), node.get("darkness"), node.get("permanent"))
		if load_kind == "enemy":
			node.set_meta("planning_actor_kind", "enemy")
			node.set_meta("planning_spawn_transform", node.transform)
			node.global_position.y = float(record.get("y", 1.0))
			if node.has_method("set_target"):
				node.call("set_target", session.main_player)
		placed.append(node)
		loaded += 1
	_update_status()
	if controls != null:
		controls.call("_update_history_buttons")
	return {"loaded": loaded, "skipped": skipped}


func clear_layout(update_status: bool = true) -> void:
	workstation_transforms.clear()
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


# Tall enemies (capsule up to 2.9 m) must start above the floor, not inside it.
func _enemy_spawn_height(enemy: Node) -> float:
	var shape_node := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		return maxf(1.0, (shape_node.shape as CapsuleShape3D).height * 0.5 + 0.1)
	return 1.0
