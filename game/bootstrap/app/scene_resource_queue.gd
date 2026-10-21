extends RefCounted
## Bounded payload loading; Dummy rendering stays entirely on the main thread.
const PREPARATION := preload("res://game/bootstrap/app/scene_resource_preparation.gd")
const MAX_IN_FLIGHT := 2
const MEMORY_HEADROOM := 128 * 1024 * 1024
var resources: Array[Resource] = []
var stats := {"peak_in_flight": 0, "resource_wait_usec": 0, "loaded": 0}
var _scripts := PREPARATION.new()

# Dummy mesh storage also races with main-thread effects during one worker load.
# Actual Compatibility/Forward+ renderers retain the two-request pipeline.
var _background_loading := DisplayServer.get_name() != "headless"
var concurrency_limit := MAX_IN_FLIGHT if _background_loading else 1


func load_all(initial: Array[String], tree: SceneTree, progress: Callable) -> String:
	resources.clear()
	stats = {"peak_in_flight": 0, "resource_wait_usec": 0, "loaded": 0}
	var paths: Array[String] = []
	var known: Dictionary = {}
	for path in initial:
		if not known.has(path):
			known[path] = true
			paths.append(path)
	var pending: Dictionary = {}
	var foreground: Dictionary = {}
	var next := 0
	var completed := 0
	var reported := 0.0
	var baseline := OS.get_static_memory_usage()
	var problem := ""
	while next < paths.size() or not pending.is_empty():
		while problem.is_empty() and next < paths.size() and pending.size() < concurrency_limit:
			if not pending.is_empty() and OS.get_static_memory_usage() > baseline + MEMORY_HEADROOM:
				break
			var path := paths[next]
			if not await _scripts.prepare(path, tree):
				problem = "cannot prepare scene scripts: " + path
				break
			var requested_at := Time.get_ticks_usec()
			if _background_loading:
				if ResourceLoader.load_threaded_request(path, "PackedScene", false) != OK:
					problem = "cannot request scene: " + path
					break
			else:
				foreground[path] = ResourceLoader.load(path, "PackedScene")
			pending[path] = requested_at
			next += 1
			stats.peak_in_flight = maxi(stats.peak_in_flight, pending.size())
		for path: String in pending.keys():
			var status := ResourceLoader.load_threaded_get_status(path) if _background_loading else ResourceLoader.THREAD_LOAD_LOADED
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			stats.resource_wait_usec += Time.get_ticks_usec() - int(pending[path])
			pending.erase(path)
			if status != ResourceLoader.THREAD_LOAD_LOADED:
				problem = "cannot load scene: " + path
				continue
			var packed := (ResourceLoader.load_threaded_get(path) if _background_loading else foreground[path]) as PackedScene
			foreground.erase(path)
			if packed == null:
				problem = "not a scene: " + path
				continue
			resources.append(packed)
			completed += 1
			stats.loaded = completed
			_discover_models(packed, paths, known)
		if not problem.is_empty():
			# ResourceLoader has no cancellation: drain issued jobs before releasing.
			next = paths.size()
		reported = maxf(reported, minf(0.99, float(completed) / maxi(paths.size(), 1)))
		progress.call(0.15 + 0.35 * reported, "resources")
		if not pending.is_empty() or next < paths.size():
			await tree.process_frame
	if not problem.is_empty():
		resources.clear()
	else:
		progress.call(0.5, "resources")
	return problem


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
