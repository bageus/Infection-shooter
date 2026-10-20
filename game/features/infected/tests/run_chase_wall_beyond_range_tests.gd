extends SceneTree
const ROUTE := preload("res://game/features/infected/chase_route.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var actor := CharacterBody3D.new()
	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .35
	capsule.height = 1.8
	body.shape = capsule
	actor.add_child(body)
	stage.add_child(actor)
	actor.position = Vector3(-12, 1, 0)
	var target := Node3D.new()
	stage.add_child(target)
	target.position = Vector3(2, 1, 0)
	# The wall is more than 10 m from the target, so the enemy meets it while still "far".
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	stage.add_child(wall)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.3, 3, 5)
	shape.shape = box
	wall.add_child(shape)
	shape.position = Vector3(-10, 1.5, 0)
	await physics_frame
	var route := ROUTE.new()
	var reached := -1.0
	for tick in 1200:
		await physics_frame
		var dir: Vector3 = route.direction(actor, target, .35)
		actor.velocity = dir * 3.0
		actor.move_and_slide()
		if actor.position.distance_to(target.position) <= 1.5:
			reached = float(tick) / 60.0
			break
	print("Reached target after %.2f s, actor at %s" % [reached, actor.position])
	_check(reached >= 0.0, "Enemy beyond 10 m behind a wall reaches the target instead of sticking")
	stage.queue_free()
	await process_frame
	print("Chase wall beyond range tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
