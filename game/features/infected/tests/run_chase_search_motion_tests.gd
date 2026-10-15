extends SceneTree
const ROUTE := preload("res://game/features/infected/chase_route.gd")
const BUDGET := preload("res://game/features/infected/public/chase_search_budget.gd")
var failures := 0

class SlowRoute extends RefCounted:
	var starts := 0
	var expansions_last_slice := 1
	func begin_search(_actor: CharacterBody3D, _target: Node3D) -> void:
		starts += 1
	func step_search(_deadline: int, _expansions: int) -> bool:
		return false
	func cancel_search() -> void:
		pass

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
	stage.add_child(wall)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.3, 3, 5)
	shape.shape = box
	wall.add_child(shape)
	shape.position.y = 1.5
	var budget := BUDGET.new()
	stage.add_child(budget)
	budget.set_physics_process(false)
	budget.expansions_per_frame = 1
	budget.time_budget_usec = 100000
	await physics_frame
	await _moving_goal(budget, actor, target)
	await _cooldown(budget, actor, target)
	_displacements(budget, actor, target)
	stage.free()
	await process_frame
	print("Chase search motion tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _moving_goal(budget: Node, actor: CharacterBody3D, target: Node3D) -> void:
	var route := ROUTE.new()
	route.configure_budget(budget)
	var initial: int = budget.total_searches
	for tick in 240:
		await physics_frame
		# Ordinary motion crosses the old 1.41 m threshold repeatedly while A* is sliced.
		target.position.z = 2.0 * sin(float(tick) * .15)
		route.direction(actor, target, .35)
		budget.call("_physics_process", 1.0 / 60.0)
		if budget.total_searches > initial:
			break
	_check(budget.total_searches == initial + 1, "A moving target cannot starve a bounded incremental search")
	_check(not route.path.is_empty(), "Moving-target search produces a path around the wall")
	var from := actor.position
	for point: Vector3 in route.path:
		_check(route.clear_segment(from, point), "Completed moving-target path has real physics clearance")
		from = point
	_check(from.x > 0.0, "Completed path reaches the other side of the wall")
	route.release()
	target.position.z = 0.0

func _cooldown(budget: Node, actor: CharacterBody3D, target: Node3D) -> void:
	var route := ROUTE.new()
	route.configure_budget(budget)
	route.search_requested(actor, target)
	var due: int = route.get("_next_search")
	target.position.z = 2.0
	# An obstructed stale waypoint must stop motion but cannot erase the retry cooldown.
	route.path = [Vector3(3, 1, 0)]
	for tick in 10:
		await physics_frame
		route.direction(actor, target, .35)
		_check(budget.pending_count() == 0, "Moved goal and failed waypoint respect completion cooldown")
		_check(route.get("_next_search") == due, "Failed path probe cannot reset the retry clock")
	while Engine.get_physics_frames() < due:
		await physics_frame
	route.direction(actor, target, .35)
	_check(budget.pending_count() == 1, "Stale path is refreshed once its cooldown expires")
	for index in 20:
		route.direction(actor, target, .35)
	_check(budget.pending_count() == 1, "Repeated stale-path requests remain deduplicated")
	route.release()
	target.position.z = 0.0

func _displacements(budget: Node, actor: CharacterBody3D, target: Node3D) -> void:
	var route := SlowRoute.new()
	var origin := actor.position
	var goal := target.position
	budget.request(route, actor, target)
	budget.call("_physics_process", 0.0)
	actor.position.x += 1.0
	target.position.z += 2.0
	budget.call("_physics_process", 0.0)
	_check(route.starts == 1, "Normal actor/target motion preserves the frontier")
	target.position.z = goal.z + 6.1
	budget.call("_physics_process", 0.0)
	_check(route.starts == 2, "Target relocation beyond six metres restarts the search")
	actor.position.x += 3.1
	budget.call("_physics_process", 0.0)
	_check(route.starts == 3, "Actor teleport beyond three metres restarts the search")
	budget.cancel(route)
	actor.position = origin
	target.position = goal

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
