extends RefCounted
## Bounded background payload loading; scripts still compile on the main thread.
const PREPARATION := preload("res://game/bootstrap/app/scene_resource_preparation.gd")
const MAX_IN_FLIGHT := 2
const MEMORY_HEADROOM := 128 * 1024 * 1024
var resources: Array[Resource] = []
var stats := {"peak_in_flight": 0, "resource_wait_usec": 0, "loaded": 0}
var _scripts := PREPARATION.new()

# Godot 4.7 Dummy mesh storage races when worker imports overlap.
# Actual Compatibility/Forward+ renderers retain the two-request pipeline.
var concurrency_limit := 1 if DisplayServer.get_name() == "headless" else MAX_IN_FLIGHT


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
			if ResourceLoader.load_threaded_request(path, "PackedScene", false) != OK:
				problem = "cannot request scene: " + path
				break
			pending[path] = Time.get_ticks_usec()
			next += 1
			stats.peak_in_flight = maxi(stats.peak_in_flight, pending.size())
		for path: String in pending.keys():
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			stats.resource_wait_usec += Time.get_ticks_usec() - int(pending[path])
			pending.erase(path)
			if status != ResourceLoader.THREAD_LOAD_LOADED:
				problem = "cannot load scene: " + path
				continue
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
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
