extends SceneTree
const ROUTE := preload("res://game/features/infected/chase_route.gd")
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


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
