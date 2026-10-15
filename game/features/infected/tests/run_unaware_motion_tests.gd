extends SceneTree
## Standing skips sliding; external forces and loss of support wake immediately.
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const PERCEPTION := preload("res://game/features/infected/enemy_perception.gd")
var failures := 0
var stage: Node3D

class Senses:
	extends PERCEPTION
	var slides := 0
	var batches := 0
	func _slide(actor: PERCEPTION.ACTOR) -> void:
		slides += 1
		super(actor)
	func _collide(actor: PERCEPTION.ACTOR, motion: Vector3) -> void:
		batches += 1
		super(actor, motion)

class StraightRoute:
	extends PERCEPTION.ROUTE
	func direction(actor: CharacterBody3D, goal: Node3D, _radius: float, _far := false) -> Vector3:
		var offset := goal.global_position - actor.global_position
		offset.y = 0.0
		return offset.normalized()

class Prop:
	extends StaticBody3D
	var pushes := 0
	func push_from_character(_at: Vector3, _motion: Vector3, _strength: float) -> void:
		pushes += 1

func _initialize() -> void:
	call_deferred("_run")

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _lod_checks(enemy: PERCEPTION.ACTOR, target: Node3D, senses: Senses) -> void:
	# All three phases must retain time/speed and immediately bypass the scheduler.
	for phase in 3:
		enemy._lod_frame_offset = phase
		target.position = enemy.position + Vector3(0, 0, 20)
		enemy.rotation.y = 0.0
		senses._home = enemy.position
		senses._home_ready = true
		senses._state_time = 0.0
		senses._idle_elapsed = 0.0
		senses.wander_enabled = true
		senses._wandering = true
		senses._wander = enemy.position + Vector3.RIGHT * 3.0
		senses.batches = 0
		senses.slides = 0
		var start := enemy.position
		await _frames(60)
		var expected := enemy.move_speed * enemy._mobility * PERCEPTION.WANDER_FACTOR
		_check(absf(enemy.position.x - start.x - expected) < 0.12, "Medium LOD preserves walking speed for phase %d" % phase)
		_check(senses.batches >= 19 and senses.batches <= 21 and senses.slides == 0, "Medium LOD uses one collision step per three frames")
		_check(absf(senses._state_time - 1.0) < 0.06, "Medium LOD clocks include skipped ticks")
		# Inject between scheduled ticks; full calculation must happen next tick.
		enemy.apply_player_push(Vector3.LEFT, 2.0)
		await _frames(1)
		_check(senses.slides == 1, "Medium LOD push bypasses every scheduler phase")
		senses.wander_enabled = false
		await _frames(45)
	# A distant actor also wakes immediately, rather than waiting up to 12 ticks.
	target.position = enemy.position + Vector3(0, 0, 60)
	senses.slides = 0
	enemy.apply_blast_stun(0.5, 1.0)
	await _frames(1)
	_check(senses.slides == 1, "Far idle blast stun bypasses the scheduler")
	await _frames(40)
	# Cached radius follows authoring changes and a replaced shape.
	var original := enemy.collision_shape.shape as CapsuleShape3D
	var copy := original.duplicate() as CapsuleShape3D
	enemy.collision_shape.shape = copy
	_check(is_equal_approx(senses._idle_body.radius(enemy.collision_shape, 1.0), copy.radius), "Radius cache follows shape replacement")
	copy.radius *= 1.1
	_check(is_equal_approx(senses._idle_body.radius(enemy.collision_shape, 2.0), copy.radius * 2.0), "Radius cache follows resource changes and scale")
	enemy.collision_shape.shape = original


func _corner_contact(enemy: PERCEPTION.ACTOR, senses: Senses) -> void:
	enemy.set_physics_process(false)
	var start := enemy.position
	var prop := Prop.new()
	prop.position = Vector3(start.x, 0, start.z)
	for side in 2:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.2, 3, 4) if side == 0 else Vector3(4, 3, 0.2)
		shape.shape = box
		shape.position = Vector3(1.2, 1.5, 0) if side == 0 else Vector3(0, 1.5, 1.6)
		prop.add_child(shape)
	stage.add_child(prop)
	await _frames(2)
	enemy._intended_motion = Vector3(1, 0, 1)
	senses._collide(enemy, Vector3(2, 0, 2))
	var travel := enemy.position - start
	_check(travel.z > travel.x + 0.2, "Batched collision retains tangential travel to the second corner face")
	_check(prop.pushes == 1, "Two contacts with one prop push it exactly once")
	_far_contact(enemy, senses, prop, start)
	prop.queue_free()
	enemy.position = start
	await _frames(2)
	enemy.set_physics_process(true)


func _far_contact(enemy: PERCEPTION.ACTOR, senses: Senses, prop: Prop, start: Vector3) -> void:
	var saved_route := enemy._route
	var saved_speed := enemy.move_speed
	enemy.position = start
	enemy._target.position = start + Vector3(0, 0, 60)
	enemy._route = StraightRoute.new()
	enemy.move_speed = 8.0
	enemy._lod_frame_offset = Engine.get_physics_frames() % 12
	senses.wander_enabled = true
	senses._wandering = true
	senses._state_time = 0.0
	senses._wander = start + Vector3(2, 0, 2)
	senses._idle_elapsed = 0.8 - 1.0 / 60.0
	prop.pushes = 0
	senses.step_unaware(enemy, 1.0 / 60.0)
	var travel := enemy.position - start
	_check(absf(travel.x - travel.z) < 0.03, "Far idle retains its original single collision step without sliding")
	_check(prop.pushes == 0, "Far idle does not introduce prop pushes")
	enemy._route = saved_route
	enemy.move_speed = saved_speed
	senses.wander_enabled = false


func _run() -> void:
	seed(42)
	var bins := {}
	for i in 90:
		var phase := PERCEPTION.new()._sight_wait
		_check(phase >= 0.0 and phase <= PERCEPTION.SIGHT_CHECK_SECONDS, "Initial sight phase is within its period")
		bins[int(phase * 60)] = true
	_check(bins.size() > 6, "Initial sight checks are spread across physics frames")
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	var target := Node3D.new()
	target.position = Vector3(0, 0, 10)
	stage.add_child(target)
	var enemy := HUNGER.instantiate()
	enemy.position.y = 0.1
	stage.add_child(enemy)
	var senses := Senses.new()
	enemy._senses = senses
	enemy.watch_target(target)
	senses.wander_enabled = false
	await _frames(30)
	_check(enemy.is_on_floor(), "Fixture settled on its floor")
	senses.slides = 0
	await _frames(30)
	_check(senses.slides == 0, "A supported idle enemy never calls move_and_slide")
	var before: Vector3 = enemy.position
	enemy.apply_player_push(Vector3.RIGHT, 3.0)
	await _frames(1)
	_check(senses.slides > 0 and enemy.position.x > before.x, "Push resumes sliding on the next tick")
	await _frames(45)
	senses.slides = 0
	enemy.apply_blast_stun(1.0, 1.0)
	await _frames(1)
	_check(senses.slides > 0, "Blast stun bypasses the idle shortcut immediately")
	await _frames(70)
	await _lod_checks(enemy, target, senses)
	await _corner_contact(enemy, senses)
	# Loss of support must work despite the stale CharacterBody floor flag.
	senses.slides = 0
	floor_body.queue_free()
	await _frames(4)
	_check(senses.slides > 0 and not enemy.is_on_floor() and enemy.velocity.y < 0, "Removing the floor resumes gravity and sliding")
	# Damage from a blast must retain the existing immediate CHASE transition.
	enemy.take_blast_damage(1.0, enemy.position + Vector3.LEFT)
	_check(enemy.is_alerted(), "Blast damage immediately alerts the enemy")
	stage.queue_free()
	await process_frame
	print("Unaware motion tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)
