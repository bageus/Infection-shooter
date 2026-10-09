extends RefCounted
## Compile scene scripts on the main thread before background resource loading.
## Godot 4.7 worker-side preload compilation can stall and leak temporary tokens.
var _scripts: Array[Script] = []
var _visited: Dictionary = {}


func prepare(path: String, tree: SceneTree) -> bool:
	var pending: Array[String] = [path]
	var started := Time.get_ticks_msec()
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if _visited.has(current):
			continue
		_visited[current] = true
		for dependency: String in ResourceLoader.get_dependencies(current):
			var target: String = dependency.split("::")[-1]
			if target.ends_with(".gd"):
				var script := load(target) as Script
				if script == null:
					return false
				_scripts.append(script)
			elif target.ends_with(".tscn") or target.ends_with(".scn") or target.ends_with(".glb"):
				pending.append(target)
			if Time.get_ticks_msec() - started >= 4:
				await tree.process_frame
				started = Time.get_ticks_msec()
	return true
