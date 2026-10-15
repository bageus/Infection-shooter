extends SceneTree
## Isolated real-physics routing workload; no rendering/animation/perception cost.
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const BUDGET := preload("res://game/features/infected/public/chase_search_budget.gd")
class MeasuredRoute extends "res://game/features/infected/chase_route.gd":
	var starts := 0
	var restarts := 0
	var finishes := 0
	func begin_search(actor: CharacterBody3D, target: Node3D) -> void:
		starts += 1
		if not _search_state.is_empty():
			restarts += 1
		super.begin_search(actor, target)
	func step_search(deadline: int, expansions: int = 4) -> bool:
		var done := super.step_search(deadline, expansions)
		if done:
			finishes += 1
		return done

var stage: Node3D
var target: Node3D
var budget: Node
var actors: Array[CharacterBody3D] = []
var routes: Array[MeasuredRoute] = []
var times: Array[int] = []
var tick := 0
var ticks := 239
var previous := 0
var full_enemies := false
var first_exit := -1
var exited: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--full-enemies":
			full_enemies = true
		if arg.begins_with("--ticks="):
			ticks = int(arg.trim_prefix("--ticks="))
	call_deferred("_setup")

func _setup() -> void:
	seed(781)
	stage = Node3D.new()
	root.add_child(stage)
	target = Node3D.new()
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
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60, .2, 60)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -.1
	stage.add_child(floor_body)
	budget = BUDGET.new()
	stage.add_child(budget)
	budget.set_physics_process(false)
	for index in 90:
		var actor := _make_actor(index)
		actors.append(actor)
		var route := MeasuredRoute.new()
		route.configure_budget(budget)
		routes.append(route)
		if full_enemies:
			actor.set("_route", route)
			actor.call("set_target", target)
			actor.set_physics_process(false)
	await physics_frame
	previous = Time.get_ticks_usec()
	physics_frame.connect(_step)

func _make_actor(index: int) -> CharacterBody3D:
	var actor: CharacterBody3D = HUNGER.instantiate() if full_enemies else CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	stage.add_child(actor)
	actor.position = Vector3(-3 - (index / 10) * .08, 1, (index % 10 - 4.5) * .22)
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = .35
	collider.shape = sphere
	if not full_enemies:
		actor.add_child(collider)
	else:
		collider.free()
	return actor

func _step() -> void:
	var now := Time.get_ticks_usec()
	if tick > 0:
		times.append(now - previous)
	previous = now
	if tick == ticks:
		_report()
		return
	target.position.z = 2.0 * sin(float(tick) / 60.0 * 1.2)
	for index in actors.size():
		if full_enemies:
			actors[index].call("_physics_process", 1.0 / 60.0)
		else:
			var direction := routes[index].direction(actors[index], target, .35)
			actors[index].move_and_collide(direction * (2.5 / 60.0))
		if actors[index].position.x > .6 and not exited.has(index):
			exited[index] = tick
			if first_exit < 0:
				first_exit = tick
	budget.call("_physics_process", 1.0 / 60.0)
	tick += 1

func _report() -> void:
	physics_frame.disconnect(_step)
	var starts := 0
	var restarts := 0
	var finishes := 0
	var with_path := 0
	for route in routes:
		starts += route.starts
		restarts += route.restarts
		finishes += route.finishes
		if not route.path.is_empty():
			with_path += 1
	var sum_usec := 0
	for usec in times:
		sum_usec += usec
	times.sort()
	print(JSON.stringify({"ticks": tick, "full_enemies": full_enemies, "starts": starts, "restarts": restarts,
		"total_searches": budget.total_searches, "finished_fraction": float(finishes) / maxi(1, starts),
		"with_path": with_path, "exited": exited.size(), "first_exit_tick": first_exit,
		"wall_mean_ms": float(sum_usec) / times.size() / 1000.0,
		"wall_p95_ms": times[int(times.size() * .95)] / 1000.0}))
	for route in routes:
		route.release()
	routes.clear()
	stage.free()
	quit()
