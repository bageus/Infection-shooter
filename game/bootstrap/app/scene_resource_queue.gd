extends RefCounted
## Bounded payload loading; Dummy rendering stays entirely on the main thread.
const PREPARATION := preload("res://game/bootstrap/app/scene_resource_preparation.gd")
const REQUEST := preload("res://game/bootstrap/app/scene_resource_request.gd")
const MAX_IN_FLIGHT := 2
const MEMORY_HEADROOM := 128 * 1024 * 1024
var resources: Array[Resource] = []
var stats := {"peak_in_flight": 0, "resource_wait_usec": 0, "loaded": 0}
var _scripts := PREPARATION.new()
var timeout_msec := 120000

# Dummy mesh storage also races with main-thread effects during one worker load.
# Actual Compatibility/Forward+ renderers retain the two-request pipeline.
var _background_loading := DisplayServer.get_name() != "headless"
var concurrency_limit := MAX_IN_FLIGHT if _background_loading else 1


func load_all(initial: Array[String], tree: SceneTree, progress: Callable, alive: Callable = Callable()) -> String:
	resources.clear()
	stats = {"peak_in_flight": 0, "resource_wait_usec": 0, "loaded": 0}
	if not REQUEST.allowed(alive): return "loading cancelled"
	var paths: Array[String] = []
	var known: Dictionary = {}
	for path in initial:
		if not known.has(path):
			known[path] = true
			paths.append(path)
	var pending: Dictionary = {}
	var next := 0
	var completed := 0
	var reported := 0.0
	var baseline := OS.get_static_memory_usage()
	var problem := ""
	while next < paths.size() or not pending.is_empty():
		if not REQUEST.allowed(alive):
			problem = "loading cancelled"
			break
		problem = _pending_interruption(pending, alive)
		if not problem.is_empty(): break
		while problem.is_empty() and next < paths.size() and pending.size() < concurrency_limit:
			if not pending.is_empty() and OS.get_static_memory_usage() > baseline + MEMORY_HEADROOM:
				break
			var path := paths[next]
			problem = await _prepare(path, tree, alive)
			if not problem.is_empty():
				break
			var request := _new_request(path)
			var error := request.start()
			if error != OK:
				problem = ("scene is still loading; wait before retrying: " if error == ERR_BUSY else "cannot request scene: ") + path
				break
			pending[path] = request
			next += 1
			stats.peak_in_flight = maxi(stats.peak_in_flight, pending.size())
		for path: String in pending.keys():
			var request: REQUEST = pending[path]
			var status := request.status()
			problem = request.interruption(status, timeout_msec, alive) if problem.is_empty() else problem
			if not problem.is_empty(): break
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			stats.resource_wait_usec += request.elapsed_usec()
			pending.erase(path)
			var packed := request.take() as PackedScene
			if status != ResourceLoader.THREAD_LOAD_LOADED:
				problem = "cannot load scene: " + path
				continue
			if packed == null:
				problem = "not a scene: " + path
				continue
			resources.append(packed)
			completed += 1
			stats.loaded = completed
			_discover_models(packed, paths, known)
		if not problem.is_empty():
			break
		var fraction := float(completed)
		for request: REQUEST in pending.values(): fraction += clampf(request.fraction, 0.0, 0.99)
		reported = maxf(reported, minf(0.99, fraction / maxi(paths.size(), 1)))
		progress.call(0.15 + 0.35 * reported, "resources")
		if not _background_loading or not pending.is_empty() or next < paths.size():
			await tree.process_frame
	if not problem.is_empty():
		for request: REQUEST in pending.values():
			stats.resource_wait_usec += request.elapsed_usec()
			request.abandon(tree)
		resources.clear()
		_scripts = PREPARATION.new()
	else:
		progress.call(0.5, "resources")
	return problem


func _new_request(path: String) -> REQUEST:
	return REQUEST.new(path, _background_loading, _scripts)


func _pending_interruption(pending: Dictionary, alive: Callable) -> String:
	for request: REQUEST in pending.values():
		var problem := request.interruption(request.status(), timeout_msec, alive)
		if not problem.is_empty(): return problem
	return ""


func _prepare(path: String, tree: SceneTree, alive: Callable) -> String:
	var started := Time.get_ticks_msec()
	var check := func() -> bool:
		return REQUEST.allowed(alive) and Time.get_ticks_msec() - started < timeout_msec
	if await _scripts.prepare(path, tree, check): return ""
	if not REQUEST.allowed(alive): return "loading cancelled: " + path
	if Time.get_ticks_msec() - started >= timeout_msec: return "scene script preparation timed out: " + path
	return "cannot prepare scene scripts: " + path


func _discover_models(packed: PackedScene, paths: Array[String], known: Dictionary) -> void:
	# model_path is deliberately a string and is absent from scene dependencies.
	var state := packed.get_state()
	for node in state.get_node_count():
		for property in state.get_node_property_count(node):
			if state.get_node_property_name(node, property) == &"model_path":
				var model: String = state.get_node_property_value(node, property)
				if not model.is_empty() and not known.has(model) and ResourceLoader.exists(model):
					known[model] = true
					paths.append(model)
