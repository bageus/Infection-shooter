extends SceneTree
## Infected do not collide with each other; overlapping ones steer apart instead.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const CROWD := preload("res://game/features/infected/crowd_separation.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	stage.add_child(floor_body)
	var player := Node3D.new()
	player.position = Vector3(20, 1, 0)
	stage.add_child(player)
	var crowd: Array[CharacterBody3D] = []
	for index in 12:
		var enemy := HUNGER.instantiate() as CharacterBody3D
		# A saved map stamps the old mask 3 onto placed infected.
		enemy.collision_mask = 3
		enemy.position = Vector3(-4.0 + index * 0.05, 1.0, 0.0)
		stage.add_child(enemy)
		enemy.call("set_target", player)
		crowd.append(enemy)
	for step in 90:
		await physics_frame
	var lowest := INF
	for first in crowd.size():
		_check(not crowd[first].get_collision_mask_value(2), "living infected ignore the infected layer")
		_check(crowd[first].get_collision_layer_value(2), "living infected stay on the infected layer for bullets and the player")
		for second in range(first + 1, crowd.size()):
			lowest = minf(lowest, crowd[first].global_position.distance_to(crowd[second].global_position))
	_check(lowest > 0.25, "a stack of 12 spreads out instead of staying on one spot (closest pair %.2f m)" % lowest)
	var lone := HUNGER.instantiate() as CharacterBody3D
	lone.position = Vector3(-25, 1, 20)
	stage.add_child(lone)
	await physics_frame
	await physics_frame
	_check(CROWD.spread(lone, lone.get("collision_shape")).is_zero_approx(), "a lone infected is not pushed")
	await _moving_coincident_pair(stage)
	stage.queue_free()
	await process_frame
	print("Crowd separation tests: %d failures" % failures)
	quit(failures)


func _moving_coincident_pair(stage: Node3D) -> void:
	var first := CharacterBody3D.new()
	var second := CharacterBody3D.new()
	stage.add_child(first)
	stage.add_child(second)
	first.position = Vector3(30, 1, 20)
	second.position = first.position
	CROWD.spread(first, null)
	CROWD.spread(second, null)
	await physics_frame
	first.position.x += 0.1
	second.position.x += 0.1
	var first_push := CROWD.spread(first, null)
	var second_push := CROWD.spread(second, null)
	_check(first_push.length() > 0.1, "Moving coincident bodies receive separation")
	_check(first_push.dot(second_push) < 0.0, "A moving coincident pair receives opposite pushes from one frame snapshot")
