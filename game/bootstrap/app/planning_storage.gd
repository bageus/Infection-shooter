extends RefCounted

const SAVE_PATH = "user://planned_layout.json"
const MAPS_DIR = "user://maps"
const LAYOUT_DIR = "res://game/presentation/office_floor/public/"
const AUTHORED_SCENE_PATH = LAYOUT_DIR + "base_office_layout.tscn"
# The shipped map: saved next to the baked scene from the editor and loaded
# when this computer has no planned_layout.json of its own (fresh install, Web).
const DEFAULT_MAP_PATH = LAYOUT_DIR + "base_office_map.json"

var map_name_edit: LineEdit
var map_select: OptionButton

var session: Variant
var objects: Variant
# The map as authored in the planner. Gameplay kills enemies, picks up items,
# tears paper and pushes props around; the planner edits and saves this
# authored state, never the aftermath of a fight.
var authored_layout: Dictionary = {}
# Name of an existing map the user was warned about; a second press overwrites it.
var _overwrite_pending := ""
var controls: Variant
var catalog: Variant


func configure(context: Dictionary) -> void:
	session = context["session"]
	objects = context["objects"]
	controls = context["controls"]
	catalog = context["catalog"]


func setup_widgets() -> void:
	map_name_edit = session.ui.get_node("Panel/VBox/MapManager/Name")
	map_select = session.ui.get_node("Panel/VBox/MapManager/Maps")


func _ensure_maps_dir() -> void:
	if not DirAccess.dir_exists_absolute(MAPS_DIR):
		DirAccess.make_dir_recursive_absolute(MAPS_DIR)


# Letters of any alphabet (a Russian name stays readable), digits, - and _.
# Returns "" when nothing usable is left.
static func _safe_map_name(raw_name: String) -> String:
	var safe := ""
	for ch in raw_name.strip_edges():
		if ch.to_upper() != ch.to_lower() or ch.is_valid_int() or ch == "-":
			safe += ch
		elif ch in [" ", "_", "."]:
			safe += "_"
	while "__" in safe:
		safe = safe.replace("__", "_")
	return safe.strip_edges().trim_prefix("_").trim_suffix("_").to_lower()


func _map_path(map_name: String) -> String:
	return MAPS_DIR + "/" + _safe_map_name(map_name) + ".json"


func _collect_layout_data() -> Dictionary:
	var records: Array = []
	if objects.player_spawn_defined:
		records.append({
			"scene":"res://game/features/player/public/player.tscn",
			"x":objects.player_spawn_transform.origin.x, "y":objects.player_spawn_transform.origin.y, "z":objects.player_spawn_transform.origin.z,
			"rotation_y":objects.player_spawn_transform.basis.get_euler().y * 180.0 / PI,
			"scale_x":1.0, "scale_y":1.0, "scale_z":1.0
		})
	for node in objects.placed:
		if not is_instance_valid(node):
			continue
		# The player is saved once, as its spawn point above, not where it stands.
		if str(node.get_meta("planning_actor_kind", "")) == "player":
			continue
		var scene_path = str(node.get_meta("planning_scene_path", ""))
		if scene_path.is_empty():
			continue
		var save_position = node.position
		if str(node.get_meta("planning_actor_kind", "")) == "enemy":
			node.set_meta("planning_spawn_transform", node.transform)
		records.append({
			"scene": scene_path,
			"object_id": str(node.get_meta("planning_object_id", "")),
			"desk_id": node.get_meta("planning_desk_id", ""),
			"attachment": node.get_meta("planning_attachment", ""),
			"zone": node.get_meta("planning_zone", -1),
			"x": save_position.x, "y": save_position.y, "z": save_position.z,
			"rotation_y": node.rotation_degrees.y,
			"rotation_x": node.rotation_degrees.x, "rotation_z": node.rotation_degrees.z,
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
		if node.has_method("get_decor_pose"):
			records[-1]["decor_pose"] = node.call("get_decor_pose")
		if node.has_method("has_display") and node.call("has_display"):
			records[-1]["display"] = node.call("get_display_config")
		if node.has_method("get_fixture_config"):
			var fixture: Dictionary = node.call("get_fixture_config")
			records[-1]["fixture_shape"] = str(fixture["shape"])
			records[-1]["fixture_visible_in_game"] = bool(fixture["visible_in_game"])
		if node.has_method("get_blood_config"):
			var blood: Dictionary = node.call("get_blood_config")
			records[-1]["blood_texture"] = str(blood["texture"])
			records[-1]["blood_surface"] = str(blood["surface"])
			records[-1]["blood_normal"] = blood["normal"]
			records[-1]["blood_attachment"] = node.call("get_blood_attachment")
		if node.has_method("get_authored_energy"):
			records[-1]["energy_multiplier"] = float(node.get("energy_multiplier"))
			var color: Color = node.call("get_authored_color")
			records[-1]["light_color"] = [color.r, color.g, color.b]
	return {"version": 8, "objects": records}


## Remembers the current planner layout as the authored map.
func snapshot_authored() -> void:
	authored_layout = _collect_layout_data()


## Puts the world back to the authored map when gameplay changed it: killed
## enemies and taken pickups return, pushed props go back. The player stays.
func restore_authored() -> bool:
	if authored_layout.is_empty():
		return false
	var current := _collect_layout_data()
	if _signature(current) == _signature(authored_layout):
		return false
	var records: Array = []
	for record in authored_layout.get("objects", []):
		if str((record as Dictionary).get("scene", "")) != "res://game/features/player/public/player.tscn":
			records.append(record)
	var keep_spawn: bool = objects.player_spawn_defined
	var spawn: Transform3D = objects.player_spawn_transform
	objects._apply_layout_data({"version": authored_layout.get("version", 7), "objects": records})
	objects.player_spawn_defined = keep_spawn
	objects.player_spawn_transform = spawn
	return true


# Layout fingerprint that ignores physics jitter below 5 cm / 2 degrees.
static func _signature(data: Dictionary) -> String:
	var rows: Array[String] = []
	for record in data.get("objects", []):
		var row := record as Dictionary
		rows.append("%s|%s|%s|%s|%s" % [row.get("scene", ""), snappedf(float(row.get("x", 0.0)), 0.05),
			snappedf(float(row.get("y", 0.0)), 0.05), snappedf(float(row.get("z", 0.0)), 0.05), snappedf(float(row.get("rotation_y", 0.0)), 2.0)])
	rows.sort()
	return "\n".join(rows)


func save_named_map() -> void:
	_ensure_maps_dir()
	var safe_name = _safe_map_name(map_name_edit.text)
	if safe_name.is_empty():
		controls.status.text = "Type a map name (letters, digits, - or _)"
		return
	var path = _map_path(safe_name)
	if FileAccess.file_exists(path) and _overwrite_pending != safe_name:
		_overwrite_pending = safe_name
		controls.status.text = "MAP '%s' EXISTS | press SAVE MAP again to overwrite" % safe_name
		return
	_overwrite_pending = ""
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		controls.status.text = "MAP SAVE ERROR %d" % FileAccess.get_open_error()
		return
	file.store_string(JSON.stringify(_collect_layout_data(), "	"))
	map_name_edit.text = safe_name
	_refresh_map_list(safe_name)
	controls.status.text = "MAP SAVED | " + safe_name


func load_selected_map() -> void:
	if map_select.item_count <= 0:
		controls.status.text = "NO SAVED MAPS"
		return
	var selected_name = map_select.get_item_text(map_select.selected)
	load_named_map(selected_name)


func load_named_map(map_name: String) -> void:
	var path = _map_path(map_name)
	if not FileAccess.file_exists(path):
		controls.status.text = "MAP NOT FOUND"
		return
	var report := _load_layout_from_path(path)
	if report.has("error"):
		controls.status.text = "MAP LOAD ERROR | %s: %s" % [map_name, report["error"]]
		return
	map_name_edit.text = map_name
	snapshot_authored()
	controls.status.text = "MAP LOADED | %s%s (press SAVE LAYOUT to start with it)" % [map_name, _skipped_text(report)]


func _refresh_map_list(select_name: String = "") -> void:
	if map_select == null:
		return
	map_select.clear()
	_ensure_maps_dir()
	var dir = DirAccess.open(MAPS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var index = 0
	var selected_index = -1
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".json"):
			var map_label = file_name.get_basename()
			map_select.add_item(map_label)
			if map_label == select_name:
				selected_index = index
			index += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	if selected_index >= 0:
		map_select.select(selected_index)


## Loads a layout file; returns {"loaded", "skipped"} or {"error"}.
func _load_layout_from_path(path: String) -> Dictionary:
	var read := _read_layout_file(path)
	return read if read.has("error") else objects._apply_layout_data(read.data)


func read_startup_layout() -> Dictionary:
	var path := SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else DEFAULT_MAP_PATH
	return _read_layout_file(path)


func _read_layout_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot open map (%d)" % FileAccess.get_open_error()}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary:
		return {"error": "not a valid map file"}
	return {"data": data}


static func _skipped_text(report: Dictionary) -> String:
	var skipped := int(report.get("skipped", 0))
	return "" if skipped == 0 else " | %d missing object(s) skipped" % skipped


func save_layout() -> void:
	var data = _collect_layout_data()
	var records: Array = data.get("objects", [])
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		controls.status.text = "SAVE ERROR %d | layout not written" % FileAccess.get_open_error()
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	authored_layout = data
	# Baking the authored scene into the project only makes sense (and is only
	# possible: res:// is read-only in a build) when running from the editor.
	if OS.has_feature("editor"):
		var shipped := FileAccess.open(DEFAULT_MAP_PATH, FileAccess.WRITE)
		if shipped != null:
			shipped.store_string(JSON.stringify(data, "\t"))
			shipped.close()
		var scene_error = _save_authored_scene()
		if scene_error != OK:
			controls.status.text = "SAVED | %d objects | scene bake error %d" % [records.size(), scene_error]
			return
	controls.status.text = "SAVED | %d objects" % records.size()


func _save_authored_scene(target: String = AUTHORED_SCENE_PATH) -> Error:
	var scene_root = Node3D.new()
	scene_root.name = "BaseOfficeLayout"
	for node in objects.placed:
		if not is_instance_valid(node):
			continue
		var scene_path = str(node.get_meta("planning_scene_path", ""))
		if scene_path.is_empty():
			continue
		var copy = catalog._instantiate_asset(scene_path)
		if copy == null:
			continue
		if node.has_method("get_decor_pose"):
			copy.call("configure_decor_pose", node.call("get_decor_pose"))
		scene_root.add_child(copy)
		copy.owner = scene_root
		copy.transform = node.transform
		if node.has_meta("planning_object_id"):
			copy.set_meta("planning_object_id", node.get_meta("planning_object_id"))
		if node.has_method("has_display") and node.call("has_display"):
			copy.call("configure_display", node.call("get_display_config"))
		if node.has_method("get_fixture_config"):
			var fixture: Dictionary = node.call("get_fixture_config")
			copy.call("configure_fixture", str(fixture["shape"]), bool(fixture["visible_in_game"]))
		if node.has_method("get_blood_config"):
			var blood: Dictionary = node.call("get_blood_config")
			copy.call("configure_blood", str(blood["texture"]), str(blood["surface"]))
			copy.call("configure_blood_normal", node.get("surface_normal"))
			copy.call("configure_blood_attachment", node.call("get_blood_attachment"))
		if node.has_meta("planning_desk_id"):
			copy.set_meta("planning_desk_id", node.get_meta("planning_desk_id"))
		if node.has_meta("planning_attachment"):
			copy.set_meta("planning_attachment", node.get_meta("planning_attachment"))
		if node.has_meta("planning_zone"):
			copy.set_meta("planning_zone", node.get_meta("planning_zone"))
		if copy.has_method("configure_flicker"):
			copy.set("energy_multiplier", node.get("energy_multiplier"))
			copy.call("set_authored_color", node.call("get_authored_color"))
			copy.set_meta("planning_light_energy", node.get_meta("planning_light_energy", 3.0))
			copy.set_meta("planning_light_angle", node.get_meta("planning_light_angle", 48.0))
			copy.set_meta("planning_flicker_mode", node.get_meta("planning_flicker_mode", 0))
			copy.set_meta("planning_flicker_step", node.get_meta("planning_flicker_step", 0.2))
		# An instanced scene restores its own children on load; owning them
		# here too saved a second copy of every wall and pane on each bake.
		if copy.scene_file_path.is_empty() and not scene_path.begins_with(catalog.ENVIRONMENT_ROOT + "/"):
			_assign_owner_recursive(copy, scene_root)
	var packed_layout = PackedScene.new()
	var pack_error = packed_layout.pack(scene_root)
	if pack_error != OK:
		scene_root.free()
		return pack_error
	var save_error = ResourceSaver.save(packed_layout, target)
	scene_root.free()
	return save_error


func _assign_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		_assign_owner_recursive(child, scene_owner)


func load_layout() -> void:
	var path := SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else DEFAULT_MAP_PATH
	if FileAccess.file_exists(path):
		var report := _load_layout_from_path(path)
		if report.has("error"):
			push_warning("Planned layout not loaded: %s" % report["error"])
		elif int(report.get("skipped", 0)) > 0:
			push_warning("Planned layout: %d missing object(s) skipped: %s" % [int(report["skipped"]), ", ".join(report.get("missing", []))])
	snapshot_authored()

