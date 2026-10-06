extends SceneTree
const ROUTE := preload("res://game/features/infected/chase_route.gd")
const BUDGET := preload("res://game/features/infected/public/chase_search_budget.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var actor := CharacterBody3D.new()
	stage.add_child(actor)
	actor.position = Vector3(-3, 1, 0)
	var target := Node3D.new()
	stage.add_child(target)
	target.position = Vector3(3, 1, 0)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	stage.add_child(wall)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.3, 3, 5)
	shape.shape = box
	wall.add_child(shape)
	shape.position.y = 1.5
	await physics_frame
	var route := ROUTE.new()
	var direction: Vector3 = route.direction(actor, target, .35)
	_check(not route.direct_clear(), "Wall blocks direct chase")
	_check(not direction.is_zero_approx() and absf(direction.z) > .1, "Enemy chooses a route around the wall")
	var from := actor.position
	for point: Vector3 in route.path:
		_check(route.clear_segment(from, point), "Every route segment has physics clearance")
		from = point
	_check(from.distance_to(target.position) < 1.0, "Route reaches the target side of the wall")
	await _shared_budget(stage, actor, target)
	wall.queue_free()
	await physics_frame
	await process_frame
	for i in range(7):
		await physics_frame
	direction = route.direction(actor, target, .35)
	_check(route.direct_clear() and direction.x > .99, "Opening the route returns to direct chase")
	stage.queue_free()
	await process_frame
	print("Chase route tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _shared_budget(stage: Node3D, actor: CharacterBody3D, target: Node3D) -> void:
	var budget := BUDGET.new()
	stage.add_child(budget)
	budget.set_physics_process(false)
	var routes: Array[RefCounted] = []
	for index in 7:
		var route := ROUTE.new()
		route.configure_budget(budget)
		routes.append(route)
		route.direction(actor, target, .35)
		route.direction(actor, target, .35)
	_check(budget.pending_count() == 7 and budget.total_searches == 0, "Repeated requests are deduplicated and do not search synchronously")
	for frame in 4:
		await physics_frame
		budget.call("_physics_process", 0.0)
		_check(budget.searches_last_frame <= 2, "Shared search work stays within the per-frame budget")
	_check(budget.pending_count() == 0 and budget.total_searches == 7, "FIFO eventually services every waiting route")
	for route in routes:
		_check(not route.path.is_empty(), "Each serviced enemy obtains a collision-checked route")
	var cancelled := ROUTE.new()
	cancelled.configure_budget(budget)
	cancelled.direction(actor, target, .35)
	budget.cancel(cancelled)
	var expired := ROUTE.new()
	expired.configure_budget(budget)
	expired.direction(actor, target, .35)
	expired = null
	await physics_frame
	budget.call("_physics_process", 0.0)
	_check(budget.pending_count() == 0 and budget.total_searches == 7, "Cancelled and expired requests cannot consume searches or remain pending")
	budget.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
