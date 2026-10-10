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
	await _priority_and_age(stage, actor, target)
	wall.queue_free()
	await physics_frame
	await process_frame
	for i in range(7):
		await physics_frame
	direction = route.direction(actor, target, .35)
	_check(route.direct_clear() and direction.x > .99, "Opening the route returns to direct chase")
	# A queued search that finds the way clear must store a typed empty path.
	_check(not bool(route.search_requested(actor, target)) and route.path.is_empty(), "A clear queued search leaves an empty typed path")
	stage.queue_free()
	await process_frame
	print("Chase route tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _shared_budget(stage: Node3D, actor: CharacterBody3D, target: Node3D) -> void:
	var budget := BUDGET.new()
	stage.add_child(budget)
	budget.set_physics_process(false)
	# Prove resumption with a deterministic node cap, independent of host speed.
	budget.expansions_per_frame = 8
	var routes: Array[RefCounted] = []
	for index in 7:
		var route := ROUTE.new()
		route.configure_budget(budget)
		routes.append(route)
		route.direction(actor, target, .35)
		route.direction(actor, target, .35)
	_check(budget.pending_count() == 7 and budget.total_searches == 0, "Repeated requests are deduplicated and do not search synchronously")
	var ticks := 0
	while budget.pending_count() > 0 and ticks < 240:
		ticks += 1
		await physics_frame
		budget.call("_physics_process", 0.0)
		_check(budget.searches_last_frame <= 2, "Shared search work stays within the per-frame budget")
		_check(budget.expansions_last_frame <= budget.expansions_per_frame, "Search slices obey the node expansion budget")
	_check(ticks > 4, "Expensive routes are spread across physics frames")
	_check(budget.pending_count() == 0 and budget.total_searches == 7, "Incremental priority queue eventually services every waiting route")
	for route in routes:
		_check(not route.path.is_empty(), "Each serviced enemy obtains a collision-checked route")
	# One microsecond prevents a whole A* from running to completion.
	var sliced := ROUTE.new()
	sliced.configure_budget(budget)
	sliced.direction(actor, target, .35)
	budget.time_budget_usec = 1
	budget.call("_physics_process", 0.0)
	_check(budget.pending_count() == 1 and budget.searches_last_frame == 0, "Exhausted time budget retains resumable work")
	budget.cancel(sliced)
	budget.time_budget_usec = 2000
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


func _priority_and_age(stage: Node3D, actor: CharacterBody3D, target: Node3D) -> void:
	var budget := BUDGET.new()
	stage.add_child(budget)
	budget.set_physics_process(false)
	budget.searches_per_frame = 1
	budget.expansions_per_frame = 4
	var far_route := ROUTE.new()
	far_route.configure_budget(budget)
	far_route.direction(actor, target, .35)
	var nearby := Node3D.new()
	stage.add_child(nearby)
	nearby.position = actor.position + Vector3(.3, 0, 0)
	var near_route := ROUTE.new()
	budget.request(near_route, actor, nearby)
	budget.call("_physics_process", 0.0)
	_check(budget.total_searches == 1 and far_route.get("_search_state").is_empty(), "Nearby request is serviced before an older distant request")
	var ticks := 0
	while far_route.path.is_empty() and ticks < 300:
		ticks += 1
		await physics_frame
		budget.request(near_route, actor, nearby)
		budget.call("_physics_process", 0.0)
	_check(not far_route.path.is_empty(), "Aged distant route completes under a continuous stream of nearby requests")
	print("Priority route: %d ticks with continuous nearby requests" % ticks)
	budget.cancel(far_route)
	budget.cancel(near_route)
	nearby.queue_free()
	budget.queue_free()
