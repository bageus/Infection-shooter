extends SceneTree
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 0.2, 120)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	stage.add_child(floor_body)
	var player := Node3D.new()
	player.position = Vector3(0, 1, 0)
	stage.add_child(player)
	# The camera looks along -Z from the player; one enemy is behind it, one in front.
	var camera := Camera3D.new()
	camera.position = Vector3(0, 12, 6)
	camera.look_at_from_position(camera.position, Vector3(0, 0, -6))
	camera.current = true
	stage.add_child(camera)
	var behind := _spawn(stage, player, Vector3(0, 1, 24))
	var ahead := _spawn(stage, player, Vector3(0, 1, -24))
	var behind_start := behind.global_position.distance_to(player.global_position)
	for i in 120:
		await physics_frame
	_check(bool(behind.get("offscreen")), "An enemy behind the camera is marked off-screen")
	_check(not bool(ahead.get("offscreen")), "An enemy in front of the camera is not off-screen")
	_check(behind.global_position.distance_to(player.global_position) < behind_start - 1.0, "An off-screen enemy keeps advancing on the target")
	stage.queue_free()
	await process_frame
	print("Off-screen lazy tick tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _spawn(stage: Node, player: Node3D, at: Vector3) -> CharacterBody3D:
	var enemy := HUNGER.instantiate() as CharacterBody3D
	enemy.position = at
	stage.add_child(enemy)
	enemy.call("set_target", player)
	return enemy


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
