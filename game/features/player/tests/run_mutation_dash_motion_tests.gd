extends SceneTree
const PLAYER := preload("res://game/features/player/public/player.tscn")
var failures := 0

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	_box(stage, Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	var player := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(player)
	player.set_physics_process(false)
	player.get("infection_runtime").set_physics_process(false)
	player.get("mutation_effects").set_process(false)
	player.position = Vector3(0, 0.1, 0)
	var mask := player.collision_mask
	# A character-layer blocker should not truncate a skill dash.
	var enemy := _box(stage, Vector3(0, 1, -2), Vector3(1, 2, 0.5))
	enemy.collision_layer = 2
	await physics_frame
	player.call("mutation_dash")
	for frame in 26:
		player.call("_update_move", 1.0 / 60.0)
		await physics_frame
	_expect(absf(player.position.z + 6.0) < 0.04, "Dash travels exactly6m and passes the enemy collision layer (z=%.4f)" % player.position.z)
	_expect(player.collision_mask == mask, "Dash restores the original collision mask")
	player.position = Vector3(4, 0.1, 0)
	player.velocity = Vector3.ZERO
	_box(stage, Vector3(4, 1, -3), Vector3(3, 2, 0.2))
	await physics_frame
	player.call("mutation_dash")
	for frame in 14:
		player.call("_update_move", 1.0 / 60.0)
		await physics_frame
	var stopped := player.position.z
	_expect(stopped > -3.0 and stopped < -2.0, "Scenery stops the dash before the wall")
	_expect(float(player.get("_roll_remaining")) > 0.0 and player.get("_mutation_dash_motion").active, "Wall collision keeps the skill window active")
	for frame in 14:
		player.call("_update_move", 1.0 / 60.0)
		await physics_frame
	_expect(absf(player.position.z - stopped) < 0.01 and player.collision_mask == mask, "Blocked dash stays stopped until expiry then restores collision")
	stage.queue_free()
	await process_frame
	await process_frame
	print("Mutation dash motion tests: %d failures" % failures)
	quit(failures)

func _box(parent: Node3D, at: Vector3, dimensions: Vector3) -> StaticBody3D:
	var box := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = dimensions
	shape.shape = hull
	box.add_child(shape)
	parent.add_child(box)
	box.position = at
	return box

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
