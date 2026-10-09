extends RefCounted
## Prepare a complete map before replacing it; optionally commit between frames.
const RESOURCE_PREPARATION := preload("res://game/bootstrap/app/scene_resource_preparation.gd")
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
const LAYOUT_PROPERTIES := preload("res://game/bootstrap/app/planning_layout_properties.gd")
const BLOOD_PLACEMENT := preload("res://game/bootstrap/app/planning_blood_placement.gd")
const PLAYER := "res://game/features/player/public/player.tscn"
var objects: Node
var session: Variant
var catalog: Variant
var geometry: Variant
var controls: Variant
var _resources: Array[Resource] = []
var _scripts := RESOURCE_PREPARATION.new()


func _init(editor: Node) -> void:
	objects = editor
	session = editor.session
	catalog = editor.catalog
	geometry = editor.geometry
	controls = editor.controls


func apply(data: Dictionary) -> Dictionary:
	var prepared := prepare(data)
	if prepared.has("error"):
		return prepared
	_begin(prepared)
	for entry: Dictionary in prepared.entries:
		_place(entry)
	return _finish(prepared)


func prepare(data: Dictionary) -> Dictionary:
	var problem := VALIDATOR.error(data)
	if not problem.is_empty():
		return {"error": problem}
	var prepared := _empty_plan()
	for record: Dictionary in data.objects:
		if not _stage(record, prepared):
			_discard(prepared)
			return {"error": "cannot instantiate scene: " + str(record.scene)}
	return _check_plan(data, prepared)


func prepare_async(data: Dictionary, tree: SceneTree, progress: Callable) -> Dictionary:
	var problem := VALIDATOR.error(data)
	if not problem.is_empty():
		return {"error": problem}
	var paths: Array[String] = []
	for record: Dictionary in data.objects:
		var path: String = catalog._migrate_scene_path(record.scene)
		if not path.is_empty() and path != PLAYER and ResourceLoader.exists(path) and not paths.has(path):
			paths.append(path)
	var resource_error := await _load_resources(paths, tree, progress)
	if not resource_error.is_empty():
		return {"error": resource_error}
	var prepared := _empty_plan()
	var started := Time.get_ticks_msec()
	for index in data.objects.size():
		if not _stage(data.objects[index], prepared):
			_discard(prepared)
			return {"error": "cannot instantiate scene: " + str(data.objects[index].scene)}
		if index % 16 == 15 or Time.get_ticks_msec() - started >= 4:
			progress.call(0.5 + 0.1 * float(index + 1) / data.objects.size(), "prepare")
			await tree.process_frame
			started = Time.get_ticks_msec()
	return _check_plan(data, prepared)


func _load_resources(paths: Array[String], tree: SceneTree, progress: Callable) -> String:
	var index := 0
	var started := Time.get_ticks_msec()
	while index < paths.size():
		var path := paths[index]
		if not await _scripts.prepare(path, tree):
			return "cannot prepare scene scripts: " + path
		if ResourceLoader.load_threaded_request(path, "PackedScene", false) != OK:
			return "cannot request scene: " + path
		var status := ResourceLoader.load_threaded_get_status(path)
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
			status = ResourceLoader.load_threaded_get_status(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			return "cannot load scene: " + path
		var packed := ResourceLoader.load_threaded_get(path) as PackedScene
		if packed == null:
			return "not a scene: " + path
		_resources.append(packed)
		# model_path is a string, so threaded scene loading alone does not load it.
		var state := packed.get_state()
		for node in state.get_node_count():
			for property in state.get_node_property_count(node):
				if state.get_node_property_name(node, property) == &"model_path":
					var model: String = state.get_node_property_value(node, property)
					if not model.is_empty() and ResourceLoader.exists(model) and not paths.has(model):
						paths.append(model)
		index += 1
		progress.call(0.15 + 0.35 * float(index) / paths.size(), "resources")
		if index % 16 == 0 or Time.get_ticks_msec() - started >= 4:
			await tree.process_frame
			started = Time.get_ticks_msec()
	return ""


func commit_async(prepared: Dictionary, tree: SceneTree, progress: Callable) -> Dictionary:
	_begin(prepared)
	var started := Time.get_ticks_msec()
	for index in prepared.entries.size():
		_place(prepared.entries[index])
		if index % 16 == 15 or Time.get_ticks_msec() - started >= 4:
			progress.call(0.6 + 0.35 * float(index + 1) / prepared.entries.size(), "objects")
			await tree.process_frame
			started = Time.get_ticks_msec()
	return _finish(prepared)


func _empty_plan() -> Dictionary:
	return {"entries": [], "player": {}, "missing": []}


func _stage(record: Dictionary, prepared: Dictionary) -> bool:
	var path: String = catalog._migrate_scene_path(record.scene)
	if path == PLAYER:
		prepared.player = record
		return true
	if path.is_empty() or not ResourceLoader.exists(path):
		prepared.missing.append(record.scene)
		return true
	var node: Node3D = catalog._create_asset(path)
	if node == null:
		return false
	prepared.entries.append({"node": node, "record": record, "scene": path})
	return true


func _check_plan(data: Dictionary, prepared: Dictionary) -> Dictionary:
	if not data.objects.is_empty() and prepared.entries.is_empty() and prepared.player.is_empty():
		_discard(prepared)
		return {"error": "map has no loadable objects"}
	return prepared


func _discard(prepared: Dictionary) -> void:
	for entry: Dictionary in prepared.entries:
		(entry.node as Node).free()


func _begin(prepared: Dictionary) -> void:
	objects.clear_layout(false, true)
	session.edit_history.stack.clear()
	if not prepared.player.is_empty():
		var latest: Dictionary = prepared.player
		objects.player_spawn_defined = true
		session.main_player.position = Vector3(float(latest.get("x", 0.0)), float(latest.get("y", 1.0)), float(latest.get("z", 0.0)))
		session.main_player.rotation_degrees.y = float(latest.get("rotation_y", 0.0))
		objects.player_spawn_transform = session.main_player.transform


func _place(entry: Dictionary) -> void:
	var record: Dictionary = entry.record
	var scene_path: String = entry.scene
	var node: Node3D = entry.node
	if catalog.bind_asset.is_valid():
		catalog.bind_asset.call(node)
	LAYOUT_PROPERTIES.restore(node, record)
	var load_kind = "enemy" if scene_path in catalog.ENEMY_SCENES else ""
	var target_parent = session.enemies_root if load_kind == "enemy" else session.root
	target_parent.add_child(node)
	node.position = Vector3(float(record.get("x",0.0)),float(record.get("y",0.0)),float(record.get("z",0.0)))
	node.rotation_degrees = Vector3(float(record.get("rotation_x", 0)), float(record.get("rotation_y", 0)), float(record.get("rotation_z", 0)))
	node.scale = Vector3(float(record.get("scale_x",1.0)),float(record.get("scale_y",1.0)),float(record.get("scale_z",1.0)))
	if scene_path.get_file() == "06_conference_chair.glb":
		objects._ground_conference_chair(node)
	geometry._restore_floor_surface(node, scene_path)
	node.set_meta("planning_scene_path", scene_path)
	if record.has("desk_id"):
		node.set_meta("planning_desk_id", str(record["desk_id"]))
	if record.has("attachment"):
		node.set_meta("planning_attachment", str(record["attachment"]))
	if int(record.get("zone", -1)) >= 0:
		node.set_meta("planning_zone", int(record["zone"]))
	if node.has_method("configure_fixture"):
		node.call("configure_fixture", str(record.get("fixture_shape", "point")), bool(record.get("fixture_visible_in_game", false)))
		node.call("set_planning_visual", session.active)
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
	objects.placed.append(node)


func _finish(prepared: Dictionary) -> Dictionary:
	BLOOD_PLACEMENT.restore_attachments([session.root])
	objects._update_status()
	if controls != null:
		controls.call("_update_history_buttons")
	return {"loaded": prepared.entries.size(), "skipped": prepared.missing.size(), "missing": prepared.missing}
