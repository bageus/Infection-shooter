extends SceneTree
const EFFECTS := preload("res://game/bootstrap/app/occlusion_effects.gd")
const QUEUE := preload("res://game/bootstrap/app/scene_resource_queue.gd")
var failures := 0

class Subject extends RefCounted:
	var target: WeakRef
	var calls := 0
	func set_revealed(_value: bool) -> void:
		calls += 1
	func clear() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _occlusion()
	await _resources()
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
	result = await queue.load_all([], self, func(_value: float, _phase: String) -> void: pass)
	_expect(result.is_empty() and queue.resources.is_empty(), "A repeated empty load releases retained resources")


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
