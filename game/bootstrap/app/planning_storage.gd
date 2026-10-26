extends RefCounted
const BIOMASS_BAKE := preload("res://game/bootstrap/app/planning_biomass_bake.gd")
const SURFACE_SETTINGS := preload("res://game/bootstrap/app/planning_surface_decals.gd")
const SCENE_BAKE := preload("res://game/bootstrap/app/planning_scene_bake.gd")
const PHYSICS := preload("res://game/bootstrap/app/planning_physics.gd")
const SETTLE := preload("res://game/bootstrap/app/planning_settle.gd")
const CAPTURE := preload("res://game/bootstrap/app/planning_layout_capture.gd")
const MAP_LOAD := preload("res://game/bootstrap/app/planning_map_load.gd")
const MAP_FILE := preload("res://game/bootstrap/app/planning_map_file.gd")
const WALL_FIXTURES := preload("res://game/bootstrap/app/planning_wall_fixtures.gd")
const LAYOUT_LOADER := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const WAVE_DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
const DOOR_OPTIONS := preload("res://game/bootstrap/app/planning_door_options.gd")

const SAVE_PATH = "user://planned_layout.json"
# Farthest a pushed loose prop may be and still be moved back instead of rebuilt.
const LOOSE_RETURN_RADIUS := 2.0
const MAPS_DIR = "user://maps"
const LAYOUT_DIR = "res://game/presentation/office_floor/public/"
const AUTHORED_SCENE_PATH = LAYOUT_DIR + "base_office_layout.tscn"
# The shipped map: saved next to the baked scene from the editor and loaded
# when this computer has no planned_layout.json of its own (fresh install, Web).
const DEFAULT_MAP_PATH = LAYOUT_DIR + "base_office_map.json"

var map_loading := false
var _save_notice := ""
var map_name_edit: LineEdit
var map_select: OptionButton

var session: Variant
var objects: Variant
# The map as authored in the planner. Gameplay kills enemies, picks up items,
# tears paper and pushes props around; the planner edits and saves this
# authored state, never the aftermath of a fight.
var authored_layout: Dictionary = {}
# Fingerprint of each placed node when the authored map was snapshotted, so restoring
# keeps the nodes gameplay left untouched instead of freeing and rebuilding them all.
var _node_marks: Dictionary = {}
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
	map_name_edit = session.ui.get_node("RightPanel/VBox/MapManager/Name")
	map_select = session.ui.get_node("RightPanel/VBox/MapManager/Maps")


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
	return CAPTURE.collect(objects, objects.placed)


## Publish both snapshot and fingerprints only when the complete capture is ready.
func snapshot_authored_async(tree: SceneTree, progress: Callable, alive: Callable) -> bool:
	var result := await CAPTURE.collect_async(objects, tree, progress, alive)
	if result.has("error"):
		return false
	var marks := {}
	var started := Time.get_ticks_msec()
	for index in objects.placed.size():
		var node: Node = objects.placed[index]
		if is_instance_valid(node):
			marks[node] = _mark(node)
		if index % 16 == 15 or Time.get_ticks_msec() - started >= 4:
			progress.call(0.975 + 0.025 * float(index + 1) / objects.placed.size(), "snapshot")
			await tree.process_frame
			if not alive.call():
				return false
			started = Time.get_ticks_msec()
	authored_layout = result.data
	_node_marks = marks
	return true


## Remembers the current planner layout as the authored map.
func snapshot_authored() -> void:
	authored_layout = _collect_layout_data()
	_remember_marks()


func _remember_marks() -> void:
	_node_marks.clear()
	for node in objects.placed:
		if is_instance_valid(node):
			_node_marks[node] = _mark(node)


# Cheap structural fingerprint (descendant count): breaking or detaching parts changes it.
# Visibility is not part of it because world activation toggles that during play.
static func _mark(node: Node) -> String:
	return str(_count(node))


static func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total


# Removes and returns the candidate within 5 cm / 2 degrees of the authored place, if any.
static func _take_match(candidates: Array, home: Vector3, yaw: float) -> Node3D:
	for i in candidates.size():
		var node: Node3D = candidates[i]
		if node.position.distance_to(home) <= 0.05 and absf(angle_difference(deg_to_rad(node.rotation_degrees.y), deg_to_rad(yaw))) <= deg_to_rad(2.0):
			candidates.remove_at(i)
			return node
	return null


# Loose rigid props of one scene are interchangeable when they share the same per-object
# identity (desk, object id, attachment, zone) and carry no lamp or blood settings.
static func _take_loose(candidates: Array, home: Vector3, record: Dictionary) -> Node3D:
	var best := -1
	var best_distance := LOOSE_RETURN_RADIUS
	for i in candidates.size():
		var node: Node3D = candidates[i]
		if not node is RigidBody3D or not _same_identity(node, record):
			continue
		var distance := node.position.distance_to(home)
		if distance <= best_distance:
			best = i
			best_distance = distance
	if best < 0:
		return null
	var picked: Node3D = candidates[best]
	candidates.remove_at(best)
	return picked


static func _same_identity(node: Node3D, record: Dictionary) -> bool:
	for method in ["get_fixture_config", "get_blood_config", "get_authored_energy"]:
		if node.has_method(method):
			return false
	return str(node.get_meta("planning_object_id", "")) == str(record.get("object_id", "")) \
		and str(node.get_meta("planning_desk_id", "")) == str(record.get("desk_id", "")) \
		and str(node.get_meta("planning_attachment", "")) == str(record.get("attachment", "")) \
		and int(node.get_meta("planning_zone", -1)) == int(record.get("zone", -1))


func _put_back(node: Node3D, record: Dictionary, kept: Dictionary) -> void:
	kept[node] = true
	node.position = Vector3(float(record.get("x", 0.0)), float(record.get("y", 0.0)), float(record.get("z", 0.0)))
	node.rotation_degrees = Vector3(float(record.get("rotation_x", 0)), float(record.get("rotation_y", 0)), float(record.get("rotation_z", 0)))
	node.scale = Vector3(float(record.get("scale_x", 1.0)), float(record.get("scale_y", 1.0)), float(record.get("scale_z", 1.0)))
	if node is RigidBody3D:
		(node as RigidBody3D).linear_velocity = Vector3.ZERO
		(node as RigidBody3D).angular_velocity = Vector3.ZERO
	if record.has("wall_mount") and node.has_method("configure_wall_mount"):
		node.call("configure_wall_mount", bool(record["wall_mount"]))


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
	var pending := _reusable_nodes()
	var missing: Array = []
	var unmatched: Array = []
	var kept := {}
	for record in records:
		var home := Vector3(float(record.get("x", 0.0)), float(record.get("y", 0.0)), float(record.get("z", 0.0)))
		var node := _take_match(pending.get(str(record.get("scene", "")), []), home, float(record.get("rotation_y", 0.0)))
		if node == null:
			unmatched.append(record)
			continue
		_put_back(node, record, kept)
	# Loose props that physics pushed or dropped far from home are interchangeable with each
	# other, so they go back instead of being rebuilt.
	for record in unmatched:
		var home := Vector3(float(record.get("x", 0.0)), float(record.get("y", 0.0)), float(record.get("z", 0.0)))
		var node := _take_loose(pending.get(str(record.get("scene", "")), []), home, record)
		if node == null:
			missing.append(record)
			continue
		_put_back(node, record, kept)
		if node.has_method("configure_display") and record.get("display") is Dictionary:
			node.call("configure_display", record["display"])
	objects.keep_on_clear = kept
	if missing.is_empty():
		objects.clear_layout(false, true)
	else:
		objects._apply_layout_data({"version": authored_layout.get("version", 7), "objects": missing})
	objects.keep_on_clear = {}
	SURFACE_SETTINGS.restore(session, authored_layout.get("surface_decals_v1", {}))
	_remember_marks()
	objects.player_spawn_defined = keep_spawn
	objects.player_spawn_transform = spawn
	return true


# Untouched static nodes grouped by scene path. Actors keep health and ammo, so
# they are always rebuilt; so is anything whose structure changed since the snapshot.
func _reusable_nodes() -> Dictionary:
	var pool := {}
	for node in objects.placed:
		if not is_instance_valid(node) or bool(node.get_meta("planning_existing", false)) or node.has_meta("planning_actor_kind"):
			continue
		if str(node.get_meta("planning_scene_path", "")) in catalog.ENEMY_SCENES or _node_marks.get(node, "") != _mark(node):
			continue
		var scene := str(node.get_meta("planning_scene_path", ""))
		if not pool.has(scene):
			pool[scene] = []
		pool[scene].append(node)
	return pool


# Layout fingerprint with 5 cm position, 2 degree rotation and 0.0001 scale quantization.
static func _signature(data: Dictionary) -> String:
	var rows: Array[String] = []
	for record in data.get("objects", []):
		var row := record as Dictionary
		var angles := Vector3(float(row.get("rotation_x", 0.0)), float(row.get("rotation_y", 0.0)), float(row.get("rotation_z", 0.0))).snapped(Vector3.ONE * 2.0)
		var size := Vector3(float(row.get("scale_x", 1.0)), float(row.get("scale_y", 1.0)), float(row.get("scale_z", 1.0))).snapped(Vector3.ONE * 0.0001)
		rows.append("%s|%s|%s|%s|%s|%s" % [row.get("scene", ""), snappedf(float(row.get("x", 0.0)), 0.05),
			snappedf(float(row.get("y", 0.0)), 0.05), snappedf(float(row.get("z", 0.0)), 0.05), angles, size])
	rows.sort()
	return "\n".join(rows) + "|surface_decals_v1:" + JSON.stringify(SURFACE_SETTINGS.CONFIG.normalized(data.get("surface_decals_v1", {})))


## Level checks that run on every save: group 13 signs at 1.75 m and, for the groups
## switched on in the palette, automatic light switches and fire alarm points.
func enforce_wall_fixtures() -> String:
	var toggles: Variant = controls.get("fixture_toggles") if controls != null else null
	var groups: Dictionary = toggles.options() if toggles != null and toggles.switches != null else {"switches": false, "fire": false}
	var stamps := PHYSICS.capture_anchors(objects.placed)
	var report: Dictionary = WALL_FIXTURES.apply(objects, LAYOUT_LOADER.new(objects), groups)
	PHYSICS.restore_anchors(objects.placed, stamps)
	var text := " | signs adjusted %d, wall fixtures %d" % [int(report["signs"]), int(report["fixtures"])]
	var missing: int = int(report["shortfall"]["switch"]) + int(report["shortfall"]["alarm"])
	return text + ("" if missing == 0 else ", %d without free wall space" % missing)


func save_named_map() -> void:
	if map_loading:
		return
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
	var fixtures := enforce_wall_fixtures()
	if not await _prepare_save():
		return
	var data: Dictionary = await _capture_save()
	if data.is_empty():
		return
	var result := MAP_FILE.write(path, data)
	if result.has("error"):
		map_loading = false
		controls.status.text = "MAP SAVE ERROR | " + str(result.error)
		return
	map_name_edit.text = safe_name
	_remember_level(safe_name)
	_refresh_map_list(safe_name)
	map_loading = false
	controls.status.text = "MAP SAVED | " + safe_name + fixtures + _save_notice


func load_selected_map() -> void:
	if map_loading:
		return
	if map_select.item_count <= 0:
		controls.status.text = "NO SAVED MAPS"
		return
	var selected_name = map_select.get_item_text(map_select.selected)
	load_named_map(selected_name)


func load_named_map(map_name: String) -> void:
	if map_loading:
		return
	var path = _map_path(map_name)
	if not FileAccess.file_exists(path):
		controls.status.text = "MAP NOT FOUND"
		return
	map_loading = true
	var job := MAP_LOAD.new(session, objects)
	var report: Dictionary = await job.run(path, self)
	map_loading = false
	if not is_instance_valid(session) or not session.is_inside_tree():
		return
	if report.has("error"):
		controls.status.text = "MAP LOAD ERROR | %s: %s" % [map_name, report["error"]]
		return
	map_name_edit.text = map_name
	_remember_level(_safe_map_name(map_name))
	controls.status.text = "MAP LOADED | %s%s (press SAVE LAYOUT to start with it)" % [map_name, _skipped_text(report)]


## The level chain finds its neighbours by the name of the map being played.
func _remember_level(level_name: String) -> void:
	var host: Variant = session.get("host")
	if host is Node:
		host.set("current_level", level_name)


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


func read_startup_layout(recovery_path: String = "") -> Dictionary:
	return MAP_FILE.startup(SAVE_PATH, DEFAULT_MAP_PATH) if recovery_path.is_empty() else MAP_FILE.read(recovery_path)


func _read_layout_file(path: String) -> Dictionary:
	return MAP_FILE.read(path)


static func _skipped_text(report: Dictionary) -> String:
	var skipped := int(report.get("skipped", 0))
	return "" if skipped == 0 else " | %d missing object(s) skipped; records preserved" % skipped


func save_layout() -> void:
	if map_loading:
		return
	var fixtures := enforce_wall_fixtures()
	if not await _prepare_save():
		return
	var data: Dictionary = await _capture_save()
	if data.is_empty():
		return
	var records: Array = data.get("objects", [])
	var result := MAP_FILE.write(SAVE_PATH, data)
	if result.has("error"):
		map_loading = false
		controls.status.text = "SAVE ERROR | " + str(result.error)
		return
	authored_layout = data
	# Baking the authored scene into the project only makes sense (and is only
	# possible: res:// is read-only in a build) when running from the editor.
	if OS.has_feature("editor"):
		var shipped := MAP_FILE.write(DEFAULT_MAP_PATH, data)
		if shipped.has("error"):
			map_loading = false
			controls.status.text = "SAVED | shipped map error: " + str(shipped.error)
			return
		var scene_error: Error = await _scene_bake().save_async(objects.placed.duplicate(), AUTHORED_SCENE_PATH, session, controls.status)
		if not is_instance_valid(session) or not session.is_inside_tree():
			map_loading = false
			return
		if scene_error != OK:
			map_loading = false
			controls.status.text = "SAVED | %d objects | scene bake error %d" % [records.size(), scene_error]
			return
	map_loading = false
	controls.status.text = "SAVED | %d objects%s%s" % [records.size(), fixtures, _save_notice]


func _save_authored_scene(target: String = AUTHORED_SCENE_PATH) -> Error:
	var bake := _scene_bake()
	return bake.save(objects.placed, target)


func load_layout() -> void:
	var path := SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else DEFAULT_MAP_PATH
	if FileAccess.file_exists(path):
		var report := _load_layout_from_path(path)
		if report.has("error"):
			push_warning("Planned layout not loaded: %s" % report["error"])
		elif int(report.get("skipped", 0)) > 0:
			push_warning("Planned layout: %d missing object(s) skipped: %s" % [int(report["skipped"]), ", ".join(report.get("missing", []))])
	snapshot_authored()



func _prepare_save(job: RefCounted = null) -> bool:
	_save_notice = ""
	var unresolved: Variant = objects.get("unresolved_records")
	if unresolved is Array and not unresolved.is_empty():
		_save_notice = " | %d unavailable object record(s) preserved" % unresolved.size()
	if not session.active:
		return true
	map_loading = true
	if job == null: job = SETTLE.new()
	var settled: bool = await job.run(session, objects.placed.duplicate(), controls.status)
	if not is_instance_valid(session) or not session.is_inside_tree():
		map_loading = false
		return false
	# Physics already moved desk attachments; reset the editing baseline.
	objects.workstation_transforms.clear()
	if not settled:
		map_loading = false
		controls.status.text = "NOT SAVED | " + str(job.failure_reason)
		return false
	return true


func _capture_save() -> Dictionary:
	if not session.active:
		return _collect_layout_data()
	var progress := func(_amount: float, _phase: String) -> void: controls.status.text = "CAPTURING PREPARED MAP"
	var alive := func() -> bool: return is_instance_valid(session) and session.is_inside_tree()
	var result: Dictionary = await CAPTURE.collect_async(objects, session.get_tree(), progress, alive)
	if result.has("error"):
		map_loading = false
		return {}
	var data: Dictionary = result.data
	var cache: Dictionary = await BIOMASS_BAKE.bake(session, data, controls.status)
	if not is_instance_valid(session) or not session.is_inside_tree():
		map_loading = false
		return {}
	if cache.has("error"):
		# Preserve the user's map even when the optional visual cache cannot be built.
		_save_notice += " | biomass bake failed: " + str(cache.error)
		data.erase(BIOMASS_BAKE.KEY)
		BIOMASS_BAKE.restore(session, {})
	elif cache.is_empty():
		data.erase(BIOMASS_BAKE.KEY)
		BIOMASS_BAKE.restore(session, {})
	else:
		cache["source_signature"] = preload("res://game/bootstrap/app/planning_biomass_bake.gd").signature(data.objects)
		data[BIOMASS_BAKE.KEY] = cache
		BIOMASS_BAKE.restore(session, cache)
	return data

func _scene_bake() -> RefCounted:
	var bake := SCENE_BAKE.new(catalog)
	bake.surface_settings = SURFACE_SETTINGS.capture(session)
	var container: Node = session.get("root")
	bake.biomass_cache = container.get_meta(BIOMASS_BAKE.KEY, {})
	return bake
