extends RefCounted

# Serialize, load and export planned layouts.
var planner: Variant


func _init(context: Node) -> void:
	planner = context


func _ensure_maps_dir() -> void:
	if not DirAccess.dir_exists_absolute(planner.MAPS_DIR):
		DirAccess.make_dir_recursive_absolute(planner.MAPS_DIR)


func _safe_map_name(raw_name: String) -> String:
	var value = raw_name.strip_edges()
	if value.is_empty():
		value = "map"
	var safe = ""
	for ch in value:
		if ch.is_valid_identifier() or ch.is_valid_int():
			safe += ch
		elif ch in [" ", "-", "_"]:
			safe += "_"
	while "__" in safe:
		safe = safe.replace("__", "_")
	return safe.strip_edges().to_lower()


func _map_path(map_name: String) -> String:
	return planner.MAPS_DIR + "/" + _safe_map_name(map_name) + ".json"


func _collect_layout_data() -> Dictionary:
	var objects: Array = []
	if planner.player_spawn_defined:
		objects.append({
			"scene":"res://game/features/player/public/player.tscn",
			"x":planner.player_spawn_transform.origin.x, "y":planner.player_spawn_transform.origin.y, "z":planner.player_spawn_transform.origin.z,
			"rotation_y":planner.player_spawn_transform.basis.get_euler().y * 180.0 / PI,
			"scale_x":1.0, "scale_y":1.0, "scale_z":1.0
		})
	for node in planner.placed:
		if not is_instance_valid(node):
			continue
		var scene_path = str(node.get_meta("planning_scene_path", ""))
		if scene_path.is_empty():
			continue
		var save_position = node.position
		if str(node.get_meta("planning_actor_kind", "")) == "enemy" and node.has_meta("planning_spawn_transform"):
			var enemy_spawn: Transform3D = node.get_meta("planning_spawn_transform")
			save_position = enemy_spawn.origin
		objects.append({
			"scene": scene_path,
			"desk_id": node.get_meta("planning_desk_id", ""),
			"attachment": node.get_meta("planning_attachment", ""),
			"zone": node.get_meta("planning_zone", -1),
			"x": save_position.x, "y": save_position.y, "z": save_position.z,
			"rotation_y": node.rotation_degrees.y,
			"scale_x": node.scale.x, "scale_y": node.scale.y, "scale_z": node.scale.z,
			"light_energy": node.get_meta("planning_light_energy", 0.0),
			"light_angle": node.get_meta("planning_light_angle", 48.0),
			"flicker_mode": node.get_meta("planning_flicker_mode", 0),
			"flicker_step": node.get_meta("planning_flicker_step", 0.2),
			"darkness": node.get("darkness") if node.get("darkness") != null else 0.0,
			"permanent_darkness": node.get("permanent") if node.get("permanent") != null else false,
			"spawn_x": (node.get_meta("planning_spawn_transform") as Transform3D).origin.x if node.has_meta("planning_spawn_transform") else node.position.x,
			"spawn_y": (node.get_meta("planning_spawn_transform") as Transform3D).origin.y if node.has_meta("planning_spawn_transform") else node.position.y,
			"spawn_z": (node.get_meta("planning_spawn_transform") as Transform3D).origin.z if node.has_meta("planning_spawn_transform") else node.position.z
		})
		if node.has_method("get_authored_energy"):
			objects[-1]["energy_multiplier"] = float(node.get("energy_multiplier"))
	return {"version": 5, "objects": objects}


func save_named_map() -> void:
	_ensure_maps_dir()
	var safe_name = _safe_map_name(planner.map_name_edit.text)
	var path = _map_path(safe_name)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		planner.status.text = "MAP SAVE ERROR"
		return
	file.store_string(JSON.stringify(_collect_layout_data(), "	"))
	planner.map_name_edit.text = safe_name
	_refresh_map_list(safe_name)
	planner.status.text = "MAP SAVED | " + safe_name


func load_selected_map() -> void:
	if planner.map_select.item_count <= 0:
		planner.status.text = "NO SAVED MAPS"
		return
	var selected_name = planner.map_select.get_item_text(planner.map_select.selected)
	load_named_map(selected_name)


func load_named_map(map_name: String) -> void:
	var path = _map_path(map_name)
	if not FileAccess.file_exists(path):
		planner.status.text = "MAP NOT FOUND"
		return
	_load_layout_from_path(path)
	planner.map_name_edit.text = map_name
	planner.status.text = "MAP LOADED | " + map_name


func _refresh_map_list(select_name: String = "") -> void:
	if planner.map_select == null:
		return
	planner.map_select.clear()
	_ensure_maps_dir()
	var dir = DirAccess.open(planner.MAPS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var index = 0
	var selected_index = -1
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".json"):
			var map_label = file_name.get_basename()
			planner.map_select.add_item(map_label)
			if map_label == select_name:
				selected_index = index
			index += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	if selected_index >= 0:
		planner.map_select.select(selected_index)


func _load_layout_from_path(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return
	_apply_layout_data(data as Dictionary)


func _apply_layout_data(data: Dictionary) -> void:
	planner.objects.clear_layout(false)
	var records: Array = data.get("objects", [])
	var player_records: Array = []
	for record_value: Variant in records:
		if record_value is Dictionary:
			var candidate: Dictionary = record_value
			var candidate_path = str(candidate.get("scene", ""))
			if candidate_path == "res://game/features/player/public/player.tscn":
				player_records.append(candidate)
	if not player_records.is_empty():
		planner.player_spawn_defined = true
		var latest: Dictionary = player_records[player_records.size() - 1]
		planner.main_player.position = Vector3(float(latest.get("x",0.0)),float(latest.get("y",1.0)),float(latest.get("z",0.0)))
		planner.main_player.rotation_degrees.y = float(latest.get("rotation_y",0.0))
		planner.player_spawn_transform = planner.main_player.transform
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var record: Dictionary = record_value
		var scene_path = _migrate_scene_path(str(record.get("scene", "")))
		if scene_path == "res://game/features/player/public/player.tscn":
			continue
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var node = planner.catalog._instantiate_asset(scene_path)
		if node == null:
			continue
		var load_kind = "enemy" if scene_path in [
			"res://game/features/infected/public/infected_capsule.tscn",
			"res://game/features/infected/public/mutant_level2.tscn"
		] else ""
		var target_parent = planner.enemies_root if load_kind == "enemy" else planner.root
		target_parent.add_child(node)
		node.position = Vector3(float(record.get("x",0.0)),float(record.get("y",0.0)),float(record.get("z",0.0)))
		node.rotation_degrees.y = float(record.get("rotation_y",0.0))
		node.scale = Vector3(float(record.get("scale_x",1.0)),float(record.get("scale_y",1.0)),float(record.get("scale_z",1.0)))
		if scene_path.get_file() == "06_conference_chair.glb":
			planner.geometry._ground_conference_chair(node)
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
				node.call("configure_zone", Vector2(node.scale.x * 4.0, node.scale.z * 4.0), node.get("darkness"), node.get("permanent"))
		if load_kind == "enemy":
			node.set_meta("planning_actor_kind", "enemy")
			node.set_meta("planning_spawn_transform", node.transform)
			node.global_position.y = float(record.get("y", 1.0))
			if node.has_method("set_target"):
				node.call("set_target", planner.main_player)
		planner.placed.append(node)
	planner.view._update_status()


func save_layout() -> void:
	var data = _collect_layout_data()
	var objects: Array = data.get("objects", [])
	var file = FileAccess.open(planner.SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
	var scene_error = _save_authored_scene()
	if scene_error == OK:
		planner.status.text = "SAVED | %d objects" % objects.size()
	else:
		planner.status.text = "SAVE ERROR %d" % scene_error


func _save_authored_scene() -> Error:
	var scene_root = Node3D.new()
	scene_root.name = "BaseOfficeLayout"
	for node in planner.placed:
		if not is_instance_valid(node):
			continue
		var scene_path = str(node.get_meta("planning_scene_path", ""))
		if scene_path.is_empty():
			continue
		var copy = planner.catalog._instantiate_asset(scene_path)
		if copy == null:
			continue
		scene_root.add_child(copy)
		copy.owner = scene_root
		copy.transform = node.transform
		if node.has_meta("planning_desk_id"):
			copy.set_meta("planning_desk_id", node.get_meta("planning_desk_id"))
		if node.has_meta("planning_attachment"):
			copy.set_meta("planning_attachment", node.get_meta("planning_attachment"))
		if node.has_meta("planning_zone"):
			copy.set_meta("planning_zone", node.get_meta("planning_zone"))
		if copy.has_method("configure_flicker"):
			copy.set("energy_multiplier", node.get("energy_multiplier"))
			copy.set_meta("planning_light_energy", node.get_meta("planning_light_energy", 3.0))
			copy.set_meta("planning_light_angle", node.get_meta("planning_light_angle", 48.0))
			copy.set_meta("planning_flicker_mode", node.get_meta("planning_flicker_mode", 0))
			copy.set_meta("planning_flicker_step", node.get_meta("planning_flicker_step", 0.2))
		if not scene_path.begins_with(planner.ENVIRONMENT_ROOT + "/"):
			_assign_owner_recursive(copy, scene_root)
	var packed_layout = PackedScene.new()
	var pack_error = packed_layout.pack(scene_root)
	if pack_error != OK:
		scene_root.free()
		return pack_error
	var save_error = ResourceSaver.save(packed_layout, planner.AUTHORED_SCENE_PATH)
	scene_root.free()
	return save_error


func _assign_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		_assign_owner_recursive(child, scene_owner)


func load_layout() -> void:
	if not FileAccess.file_exists(planner.SAVE_PATH):
		return
	_load_layout_from_path(planner.SAVE_PATH)


func _migrate_scene_path(old_path: String) -> String:
	var replacements = {
		"res://models/objects/01_wall_door.glb": "res://game/presentation/office_floor/public/structural/wall_door.tscn",
		"res://models/objects/01_wall_door_2.glb": "res://game/presentation/office_floor/public/structural/wall_door.tscn",
		"res://models/objects/01_wall_inner_corner.blend": "",
		"res://game/presentation/office_floor/public/structural/wall_inner_corner.tscn": ""
	}
	if replacements.has(old_path):
		return str(replacements[old_path])
	if old_path.begins_with("res://models/objects/Office_Set/"):
		return ""
	var legacy_prop = "res://game/presentation/office_floor/public/props/"
	if old_path.begins_with(legacy_prop) and old_path.ends_with(".tscn"):
		if old_path.get_file() in ["planner_light.tscn", "darkness_zone.tscn", "environment_prop.tscn"]:
			return old_path
		if old_path.get_file() == "07_table.tscn":
			return old_path
		var legacy_name = old_path.get_file().get_basename().substr(3).to_lower()
		for group in planner.group_catalogs.values():
			for entry: Dictionary in group:
				if str(entry["name"]).substr(3).replace(" ", "_").to_lower() == legacy_name:
					return str(entry["path"])
		return ""
	return old_path
