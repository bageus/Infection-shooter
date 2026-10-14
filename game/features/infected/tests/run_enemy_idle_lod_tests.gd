extends SceneTree
## Distant unaware actors retain simulation-time speed, waits and wall collision.
const PERCEPTION := preload("res://game/features/infected/enemy_perception.gd")
var failures := 0
var stage: Node3D

class Route:
	extends RefCounted
	func direction(actor: Node3D, goal: Node3D, _radius: float) -> Vector3:
		var offset := goal.global_position - actor.global_position
		offset.y = 0.0
		return offset.normalized()

class Actor:
	extends CharacterBody3D
	var _target: Node3D
	var sleep_distance := 32.0
	var _lod_frame_offset := 0
	var collision_shape: CollisionShape3D
	var move_speed := 4.0
	var _mobility := 1.0
	var _route := Route.new()
	var _blast_stun_remaining := 0.0
	var _push_velocity := Vector3.ZERO
	var push_decay := 10.0
	var _face_direction := Vector3.ZERO
	var _intended_motion := Vector3.ZERO
	var senses := PERCEPTION.new()
	func _physics_process(delta: float) -> void:
		senses.step_unaware(self, delta)
	func _turn_toward_face_direction(_delta: float) -> void:
		pass
	func _apply_gravity(_delta: float) -> void:
		pass
	func _push_chair_contacts() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _spawn(offset: int) -> Actor:
	var actor := Actor.new()
	actor._lod_frame_offset = offset
	actor.collision_layer = 0
	actor.collision_mask = 1
	actor.collision_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	actor.collision_shape.shape = capsule
	actor.add_child(actor.collision_shape)
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
	var actors: Array[Actor] = []
	for offset in 12:
		actors.append(_spawn(offset))
	for _i in 60:
		await physics_frame
	await process_frame
	for actor in actors:
		var traveled := actor.position.distance_to(actor.senses._home)
		_check(traveled > 1.2 and traveled < 1.7, "Idle LOD offset %d walks at 1.4 m/s (%f m)" % [actor._lod_frame_offset, traveled])
		_check(actor.senses._state_time > 0.8 and actor.senses._state_time < 1.3, "Idle LOD clocks advance simulation time")
		# Start the pause fixture at home: a random next goal must be at least
		# 1 m away, so arrival cannot immediately consume the resumed wander.
		actor.position = actor.senses._home
		actor._mobility = 0.0
		actor.senses._wandering = false
		actor.senses._wander_wait = 1.0
	for _i in 78:
		await physics_frame
	await process_frame
	for actor in actors:
		_check(actor.senses._wandering, "One-second idle pause expires for every LOD offset")
		_check(not actor.senses.is_chasing(), "Distant wandering does not alert the actor")
	_batched_arrival(actors[1])
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


func _batched_arrival(actor: Actor) -> void:
	actor.senses._wandering = true
	actor.senses._state_time = 0.0
	actor.senses._wander = actor.position + Vector3.RIGHT * 0.5
	var step := 0.8 # 12 distant ticks at the perception suite's 4x time scale.
	var velocity := actor.senses._idle_wander(actor, step, actor._route, 0.3, 5.4)
	_check(velocity.length() * step <= 0.501, "A batched distant step cannot overshoot the wander destination")
