extends SceneTree
## Distant unaware actors retain simulation-time speed, waits and wall collision.
const PERCEPTION := preload("res://game/features/infected/enemy_perception.gd")
var failures := 0
var stage: Node3D

class Route:
	extends "res://game/features/infected/chase_route.gd"
	func direction(actor: Node3D, goal: Node3D, _radius: float, _far := false) -> Vector3:
		var offset := goal.global_position - actor.global_position
		offset.y = 0.0
		return offset.normalized()

class Actor:
	extends "res://game/features/infected/infected_capsule.gd"
	var senses := PERCEPTION.new()
	func _ready() -> void:
		_route = Route.new()
	func _physics_process(delta: float) -> void:
		senses.step_unaware(self, delta)
	func _turn_toward_face_direction(_delta: float) -> void:
		pass
	func _apply_gravity(delta: float) -> void:
		super(delta)
	func _push_chair_contacts() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _spawn(offset: int) -> Actor:
	var actor := Actor.new()
	actor._lod_frame_offset = offset
	actor.move_speed = 4.0
	actor.collision_layer = 0
	actor.collision_mask = 1
	actor.collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	actor.collision_shape.shape = capsule
	actor.collision_shape.name = "CollisionShape3D"
	actor.add_child(actor.collision_shape)
	var visual := Node3D.new()
	visual.name = "Body"
	actor.add_child(visual)
	var cloud := Area3D.new()
	cloud.name = "DeathCloud"
	actor.add_child(cloud)
	stage.add_child(actor)
	actor.position = Vector3(offset * 8.0, 1.0, 0.0)
	actor._target = Node3D.new()
	stage.add_child(actor._target)
	actor._target.position = actor.position + Vector3(0, 0, -60)
	actor.senses.watch()
	actor.senses._home = actor.position
	actor.senses._home_ready = true
	actor.senses._wandering = true
	actor.senses._wander = actor.position + Vector3.RIGHT * 2.0
	return actor


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(220, 1, 100)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	var actors: Array[Actor] = []
	for offset in 12:
		actors.append(_spawn(offset))
	# Settle and warm every phase before measuring a complete 60-frame window.
	for actor in actors:
		actor.senses.wander_enabled = false
	for _i in 30:
		await physics_frame
	await process_frame
	for actor in actors:
		actor.senses.wander_enabled = true
		actor.senses._home = actor.position
		actor.senses._state_time = 0.0
		actor.senses._wandering = true
		actor.senses._wander = actor.position + Vector3.RIGHT * 2.0
	for _i in 60:
		await physics_frame
	await process_frame
	for actor in actors:
		var traveled := actor.position.distance_to(actor.senses._home)
		_check(traveled > 1.2 and traveled < 1.7, "Idle LOD offset %d walks at 1.4 m/s (%f m)" % [actor._lod_frame_offset, traveled])
		_check(actor.senses._state_time > 0.8 and actor.senses._state_time < 1.3, "Idle LOD clocks advance simulation time")
		# Test pause expiry, not an immediate arrival at a randomly nearby goal.
		actor.senses._home = actor.position
		actor._mobility = 0.0
		actor.senses._wandering = false
		actor.senses._wander_wait = 1.0
	for _i in 78:
		await physics_frame
	await process_frame
	for actor in actors:
		_check(actor.senses._wandering, "One-second idle pause expires for every LOD offset")
		_check(not actor.senses.is_chasing(), "Distant wandering does not alert the actor")
	await _wall_collision(actors[0])
	stage.queue_free()
	await process_frame
	print("Enemy idle LOD tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _wall_collision(actor: Actor) -> void:
	actor.set_physics_process(false)
	actor.position = Vector3(0, 1, 0)
	actor._mobility = 1.0
	actor.senses._wandering = true
	actor.senses._state_time = 0.0
	actor.senses._wander = actor.position + Vector3.RIGHT * 3.0
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 3, 4)
	shape.shape = box
	wall.add_child(shape)
	stage.add_child(wall)
	wall.position = Vector3(1.1, 1.5, 0)
	await physics_frame
	actor.set_physics_process(true)
	for _i in 120:
		await physics_frame
	await process_frame
	_check(actor.position.x > 0.4 and actor.position.x < 0.85, "Batched idle steps stop at a wall (%f)" % actor.position.x)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
