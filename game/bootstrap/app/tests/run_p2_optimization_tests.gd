extends SceneTree
const EFFECTS := preload("res://game/bootstrap/app/occlusion_effects.gd")
const QUEUE := preload("res://game/bootstrap/app/scene_resource_queue.gd")
var failures := 0

class Subject extends RefCounted:
	var target: WeakRef
	var calls := 0
	func set_revealed(_value: bool, _force_visible: bool = false) -> void:
		calls += 1
	func clear() -> void:
		pass


class MeshLoader extends ResourceFormatLoader:
	var loaded_on_main_thread := false
	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["ridprobe"])
	func _handles_type(type: StringName) -> bool:
		return type == &"PackedScene"
	func _get_resource_type(_path: String) -> String:
		return "PackedScene"
	func _load(_path: String, _original: String, _sub_threads: bool, _cache_mode: int) -> Variant:
		loaded_on_main_thread = Thread.is_main_thread()
		var scene := PackedScene.new()
		var mesh := MeshInstance3D.new()
		# Do not deliberately provoke the engine race on the failing baseline.
		if loaded_on_main_thread:
			mesh.mesh = QuadMesh.new()
			mesh.mesh.get_rid()
		scene.pack(mesh)
		mesh.free()
		return scene


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _occlusion()
	await _resources()
	await _dummy_mesh_loading()
	print("P2 optimization tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _occlusion() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var hero := Node3D.new()
	world.add_child(hero)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1, 10)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	var wall := Node3D.new()
	wall.add_to_group("camera_occluder")
	world.add_child(wall)
	var body := _box(wall, Vector3(0, 1, 2))
	# More than the previous eight pass-through hits cannot hide the actual wall.
	for index in 12:
		_box(world, Vector3(0, 1, 3 + index * 0.4))
	var effects := EFFECTS.new()
	world.add_child(effects)
	effects.setup(hero, camera, world)
	effects.set_physics_process(false)
	effects.call("_rebuild")
	await physics_frame
	await physics_frame
	_expect(effects.call("_blocked", hero), "Furniture does not consume structural queries")
	_expect(body.collision_layer == 1 | effects.QUERY_LAYER.MASK, "Query bit preserves gameplay layer")
	wall.hide()
	await physics_frame
	_expect(not effects.call("_blocked", hero), "Hidden structural root stops blocking")
	wall.show()
	body.collision_layer = 0
	await physics_frame
	_expect(not effects.call("_blocked", hero), "Destruction disables structural query with gameplay collision")
	effects.subjects.clear()
	var witnesses: Array[RefCounted] = []
	for index in 100:
		var subject := Subject.new()
		subject.target = weakref(hero)
		witnesses.append(subject)
		effects.subjects.append(subject)
	for tick in 14:
		effects.call("_physics_process", 1.0 / 60.0)
		_expect(effects.checks_last_tick <= 8 and effects.rays_last_tick <= 24, "Per-tick work has a hard bound")
	_expect(witnesses.all(func(subject: RefCounted) -> bool: return subject.calls > 0), "Round robin visits every subject")
	effects.set_runtime_enabled(false)
	_expect(body.collision_layer == 0, "Teardown never revives destroyed collision")
	world.free()
	await process_frame


func _box(parent: Node3D, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(4, 3, 0.1)
	shape.shape = bounds
	body.add_child(shape)
	parent.add_child(body)
	body.position = at
	return body


func _resources() -> void:
	var queue := QUEUE.new()
	var paths: Array[String] = [
		"res://game/bootstrap/app/tests/fixtures/layout_object.tscn",
		"res://game/presentation/office_floor/public/props/environment_prop.tscn",
		"res://game/presentation/office_floor/public/structural/floor_pad.tscn",
		"res://game/bootstrap/app/tests/fixtures/queue_model.tscn",
	]
	var values: Array[float] = []
	var result := await queue.load_all(paths, self, func(value: float, _phase: String) -> void: values.append(value))
	_expect(result.is_empty() and queue.resources.size() == 5, "Queue loads scenes and discovers string model_path")
	_expect(queue.stats.peak_in_flight == queue.concurrency_limit and queue.stats.loaded == 5, "Requests obey the renderer's fixed concurrency cap")
	for index in range(1, values.size()):
		_expect(values[index] >= values[index - 1], "Resource progress never moves backwards")
	queue.resources.clear()
	var invalid: Array[String] = [paths[0], "res://game/bootstrap/app/tests/fixtures/queue_model.gd", paths[2]]
	result = await queue.load_all(invalid, self, func(_value: float, _phase: String) -> void: pass)
	_expect(not result.is_empty() and queue.resources.is_empty(), "A non-scene payload drains jobs and discards retained resources")
	# The abandoned engine job for paths[0] drains on frames; a retry before then is refused as still loading.
	for _frame in 600:
		if ResourceLoader.load_threaded_get_status(paths[0]) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE: break
		await process_frame
	var duplicate: Array[String] = [paths[0], paths[0]]
	result = await queue.load_all(duplicate, self, func(_value: float, _phase: String) -> void: pass)
	_expect(result.is_empty() and queue.resources.size() == 1, "A queue can recover after failure and deduplicates paths")
	result = await queue.load_all([], self, func(_value: float, _phase: String) -> void: pass)
	_expect(result.is_empty() and queue.resources.is_empty(), "A repeated empty load releases retained resources")


func _dummy_mesh_loading() -> void:
	if DisplayServer.get_name() != "headless":
		return
	var path := "user://scene_queue.ridprobe"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.close()
	var loader := MeshLoader.new()
	ResourceLoader.add_resource_format_loader(loader, true)
	var queue := QUEUE.new()
	var paths: Array[String] = [path]
	var result := await queue.load_all(paths, self, func(_value: float, _phase: String) -> void: pass)
	_expect(result.is_empty() and queue.resources.size() == 1, "Dummy queue retains a mesh-bearing scene")
	_expect(loader.loaded_on_main_thread, "Dummy mesh creation must not race effects on the main thread")
	queue.resources.clear()
	ResourceLoader.remove_resource_format_loader(loader)
	DirAccess.remove_absolute(path)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
