extends RefCounted
## Prepare a complete map before replacing it; optionally commit between frames.
const SURFACE_SETTINGS := preload("res://game/bootstrap/app/planning_surface_decals.gd")
const RESOURCE_QUEUE := preload("res://game/bootstrap/app/scene_resource_queue.gd")
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
const LAYOUT_PROPERTIES := preload("res://game/bootstrap/app/planning_layout_properties.gd")
const BLOOD_PLACEMENT := preload("res://game/bootstrap/app/planning_blood_placement.gd")
const PLAYER := "res://game/features/player/public/player.tscn"
var _biomass_cache: Dictionary = {}
var objects: Node
var session: Variant
var catalog: Variant
var geometry: Variant
var controls: Variant
var _resources: Array[Resource] = []
var resource_queue := RESOURCE_QUEUE.new()
var timings := {"instantiate_usec": 0, "ready_usec": 0}


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


func prepare_async(data: Dictionary, tree: SceneTree, progress: Callable, alive: Callable = Callable()) -> Dictionary:
	_resources.clear()
	timings = {"instantiate_usec": 0, "ready_usec": 0}
	var problem := VALIDATOR.error(data)
	if not problem.is_empty():
		return {"error": problem}
	var paths := _resource_paths(data)
	var resource_error := await _load_resources(paths, tree, progress)
	if not resource_error.is_empty() or not _alive(alive):
		_discard(_empty_plan())
		return {"error": resource_error if not resource_error.is_empty() else "loading cancelled"}
	var prepared := _empty_plan()
	var started := Time.get_ticks_msec()
	for index in data.objects.size():
		if not _stage(data.objects[index], prepared):
			_discard(prepared)
			return {"error": "cannot instantiate scene: " + str(data.objects[index].scene)}
		if index % 16 == 15 or Time.get_ticks_msec() - started >= 4:
			progress.call(0.5 + 0.1 * float(index + 1) / data.objects.size(), "prepare")
			await tree.process_frame
			if not _alive(alive):
				_discard(prepared)
				return {"error": "loading cancelled"}
			started = Time.get_ticks_msec()
	return _check_plan(data, prepared)


func _resource_paths(data: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	for record: Dictionary in data.objects:
		var path: String = catalog._migrate_scene_path(record.scene)
		if not path.is_empty() and path != PLAYER and ResourceLoader.exists(path) and not paths.has(path):
			paths.append(path)
	return paths


func _load_resources(paths: Array[String], tree: SceneTree, progress: Callable) -> String:
	var problem := await resource_queue.load_all(paths, tree, progress)
	_resources.assign(resource_queue.resources)
	return problem


func commit_async(prepared: Dictionary, tree: SceneTree, progress: Callable, alive: Callable = Callable(), staged_finish: bool = false) -> Dictionary:
	if not _alive(alive):
		_discard(prepared)
		return {"error": "loading cancelled"}
	_begin(prepared)
	var started := Time.get_ticks_msec()
	for index in prepared.entries.size():
		_place(prepared.entries[index])
		if index % 16 == 15 or Time.get_ticks_msec() - started >= 4:
			progress.call(0.6 + 0.35 * float(index + 1) / prepared.entries.size(), "objects")
			await tree.process_frame
			if not _alive(alive):
				_discard(prepared)
				return {"error": "loading cancelled"}
			started = Time.get_ticks_msec()
	if staged_finish:
		progress.call(0.95, "attachments")
		var host: Node = session.get("host")
		if not await BLOOD_PLACEMENT.restore_attachments_async([session.root], tree, alive, host.get("impact_pool") if host != null else null):
			_discard(prepared)
			return {"error": "loading cancelled"}
		return _report(prepared)
	return _finish(prepared)


## Named maps clear only after preparation succeeds; keep the existing retained nodes.
func clear_async(tree: SceneTree, progress: Callable, alive: Callable) -> bool:
	objects.workstation_transforms.clear()
	objects.selected = null
	var retained: Array[Node3D] = []
	var old: Array = objects.placed.duplicate()
	var started := Time.get_ticks_msec()
	for index in old.size():
		if is_instance_valid(old[index]):
			var node: Node3D = old[index]
			if bool(node.get_meta("planning_existing", false)) or objects.keep_on_clear.has(node):
				retained.append(node)
			else:
				node.free()
		if index % 16 == 15 or Time.get_ticks_msec() - started >= 4:
			progress.call(0.6, "free")
			await tree.process_frame
			if not _alive(alive):
				return false
			started = Time.get_ticks_msec()
	objects.placed = retained
	return true


static func _alive(check: Callable) -> bool:
	return not check.is_valid() or bool(check.call())


func _empty_plan() -> Dictionary:
	return {"entries": [], "player": {}, "missing": [], "unresolved": []}


func _stage(record: Dictionary, prepared: Dictionary) -> bool:
	var path: String = catalog._migrate_scene_path(record.scene)
	if path == PLAYER:
		prepared.player = record
		return true
	if path.is_empty() or not ResourceLoader.exists(path):
		prepared.missing.append(record.scene)
		prepared.unresolved.append(record.duplicate(true))
		return true
	var started := Time.get_ticks_usec()
	var node: Node3D = catalog._create_asset(path)
	timings.instantiate_usec += Time.get_ticks_usec() - started
	if node == null:
		return false
	prepared.entries.append({"node": node, "record": record, "scene": path})
	return true


func _check_plan(data: Dictionary, prepared: Dictionary) -> Dictionary:
	prepared["surface_decals_v1"] = data.get("surface_decals_v1", {}).duplicate(true)
	var cache: Dictionary = data.get("floor_biomass_v1", {})
	prepared["floor_biomass_v1"] = cache if str(cache.get("source_signature", "")) == preload("res://game/bootstrap/app/planning_biomass_bake.gd").signature(data.objects) else {}
	# Authored restoration can retain every live node and stage only unavailable records.
	if not data.objects.is_empty() and prepared.entries.is_empty() and prepared.player.is_empty() and objects.keep_on_clear.is_empty():
		_discard(prepared)
		return {"error": "map has no loadable objects"}
	return prepared


func _discard(prepared: Dictionary) -> void:
	for entry: Dictionary in prepared.entries:
		if is_instance_valid(entry.node):
			(entry.node as Node).free()
	_resources.clear()
	resource_queue.resources.clear()


func _begin(prepared: Dictionary) -> void:
	objects.clear_layout(false, true)
	objects.unresolved_records.assign(prepared.unresolved.duplicate(true))
	_biomass_cache = prepared.get("floor_biomass_v1", {})
	preload("res://game/bootstrap/app/planning_biomass_bake.gd").restore(session, {})
	SURFACE_SETTINGS.restore(session, prepared.get("surface_decals_v1", {}))
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
	# Register physics shapes at their authored transform, never all at the origin.
	node.position = Vector3(float(record.get("x",0.0)),float(record.get("y",0.0)),float(record.get("z",0.0)))
	node.rotation_degrees = Vector3(float(record.get("rotation_x", 0)), float(record.get("rotation_y", 0)), float(record.get("rotation_z", 0)))
	node.scale = Vector3(float(record.get("scale_x",1.0)),float(record.get("scale_y",1.0)),float(record.get("scale_z",1.0)))
	# Saved chairs already have an authored height. Suppress their spawn-time
	# floor adjustment during _ready, even for maps saved before physics settling.
	var restoring_chair := scene_path.get_file() == "06_conference_chair.glb"
	if record.has("settled_physics") or restoring_chair:
		node.set_meta("planning_settled_transform", node.transform)
	if not _biomass_cache.is_empty() and not bool(session.get("active")) and node.has_method("set_floor_biomass_baked"):
		node.call("set_floor_biomass_baked", true)
	var ready_started := Time.get_ticks_usec()
	target_parent.add_child(node)
	timings.ready_usec += Time.get_ticks_usec() - ready_started
	if record.has("settled_physics"):
		node.set_meta("planning_settled_transform", node.transform)
		if node is RigidBody3D and not node.freeze:
			node.sleeping = true
	elif restoring_chair:
		node.remove_meta("planning_settled_transform")
	geometry._restore_floor_surface(node, scene_path)
	node.set_meta("planning_scene_path", scene_path)
	if record.has("desk_id"):
		node.set_meta("planning_desk_id", str(record["desk_id"]))
	if record.has("attachment"):
		node.set_meta("planning_attachment", str(record["attachment"]))
	if record.has("auto_fixture"):
		node.set_meta("planning_auto_fixture", str(record["auto_fixture"]))
	if int(record.get("zone", -1)) >= 0:
		node.set_meta("planning_zone", int(record["zone"]))
	if node.has_method("configure_fixture"):
		node.call("configure_fixture", str(record.get("fixture_shape", "point")), bool(record.get("fixture_visible_in_game", false)))
		node.call("set_planning_visual", session.active)
	if node.has_method("configure_spawn"):
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
		node.set("room_id", maxi(int(record.get("room_id", 0)), 0))
		if node.has_method("configure_zone"):
			# The restored node scale already stretches the 4 m base zone.
			node.call("configure_zone", Vector2(4.0, 4.0), node.get("darkness"), node.get("permanent"))
	if load_kind == "enemy":
		node.set_meta("planning_actor_kind", "enemy")
		node.set_meta("planning_spawn_transform", node.transform)
		node.global_position.y = float(record.get("y", 1.0))
		if node.has_method("watch_target"):
			node.call("watch_target", session.main_player)
	objects.placed.append(node)


## Adds records to the current map without clearing it; returns how many were placed.
func append(records: Array) -> int:
	var prepared := _empty_plan()
	for record: Dictionary in records:
		if not _stage(record, prepared):
			_discard(prepared)
			return 0
	for entry: Dictionary in prepared.entries:
		_place(entry)
	objects._update_status()
	return prepared.entries.size()


func _finish(prepared: Dictionary) -> Dictionary:
	var host: Node = session.get("host")
	BLOOD_PLACEMENT.restore_attachments([session.root], host.get("impact_pool") if host != null else null)
	return _report(prepared)


func _report(prepared: Dictionary) -> Dictionary:
	preload("res://game/bootstrap/app/planning_biomass_bake.gd").restore(session, prepared.get("floor_biomass_v1", {}))
	objects._update_status()
	if controls != null:
		controls.call("_update_history_buttons")
	print("Mission loading: %s; instantiate %.2f ms; add_child/_ready %.2f ms" % [resource_queue.stats, timings.instantiate_usec / 1000.0, timings.ready_usec / 1000.0])
	_resources.clear()
	resource_queue.resources.clear()
	return {"loaded": prepared.entries.size(), "skipped": prepared.missing.size(), "missing": prepared.missing}
