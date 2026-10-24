extends SceneTree
## Prepared maps must not keep impact callbacks alive; every wake route still sounds.
const WATCHER := preload("res://game/presentation/office_floor/impact_sound_watcher.gd")
const BODY_COUNT := 4000

class CountingWatcher extends "res://game/presentation/office_floor/impact_sound_watcher.gd":
	var calls := 0
	func _physics_process(delta: float) -> void:
		calls += 1
		super._physics_process(delta)

var failures := 0
var stage: Node3D
var box := BoxShape3D.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	await _prepared_batch()
	await _wake_routes()
	await _fall_again()
	stage.free()
	await process_frame
	print("Impact sound sleep tests: %d failure(s)." % failures)
	quit(0 if failures == 0 else 1)


func _body(at: Vector3, gravity := 0.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.position = at
	body.gravity_scale = gravity
	body.collision_layer = 2
	body.collision_mask = 1 if gravity > 0.0 else 0
	var collider := CollisionShape3D.new()
	collider.shape = box
	body.add_child(collider)
	stage.add_child(body)
	var watcher := CountingWatcher.new()
	watcher.name = "ImpactSound"
	watcher.event = &"fall_metal"
	body.add_child(watcher)
	return body


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
	await process_frame


func _sleep(body: RigidBody3D) -> void:
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = true
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, true)


func _calls(bodies: Array) -> int:
	var total := 0
	for body: RigidBody3D in bodies:
		total += int(body.get_node("ImpactSound").get("calls"))
	return total


func _prepared_batch() -> void:
	var bodies: Array = []
	for index in BODY_COUNT:
		bodies.append(_body(Vector3(index * 2.0, 3, 0)))
	await _ticks(3)
	paused = true
	for body: RigidBody3D in bodies:
		_sleep(body)
	paused = false
	await _ticks(3)
	var active := 0
	var awake := 0
	for body: RigidBody3D in bodies:
		if body.get_node("ImpactSound").is_physics_processing(): active += 1
		if not bool(PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING)): awake += 1
	_expect(awake == 0, "Prepared bodies remain natively asleep (%d awake)" % awake)
	_expect(active == 0, "Prepared furniture stops impact callbacks (%d active)" % active)
	var before := _calls(bodies)
	await _ticks(60)
	var extra := _calls(bodies) - before
	_expect(extra == 0, "Sleeping furniture has no steady-state impact callbacks (%d)" % extra)
	print("IMPACT_SLEEP_METRICS bodies=%d physics_ticks=60 extra_callbacks=%d" % [BODY_COUNT, extra])
	for body: RigidBody3D in bodies:
		body.free()
	await process_frame


func _wake_routes() -> void:
	var body := _body(Vector3(0, 3, 0))
	var watcher := body.get_node("ImpactSound") as CountingWatcher
	await _ticks(3)
	for manual in [false, true]:
		_sleep(body)
		await _ticks(3)
		_expect(not watcher.is_physics_processing(), "Sleep stops watching before wake route")
		var before := watcher.calls
		if manual:
			# Bullet, character and blast adapters assign this before applying an impulse.
			body.sleeping = false
		body.apply_central_impulse(Vector3.RIGHT * 2)
		await _ticks(4)
		_expect(watcher.is_physics_processing() and watcher.calls > before, "Impulse resumes watching (manual sleeping=false: %s)" % manual)
		_expect(body.linear_velocity.x > 1.0, "Watching does not change the physical push")
	# A server-only sleep transition still uses the existing native signal route.
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, true)
	await _ticks(3)
	_expect(body.sleeping and not watcher.is_physics_processing(), "Native sleep notification suspends impact observation")
	body.freeze = true
	await _ticks(3)
	_expect(not watcher.is_physics_processing(), "Frozen mounts stop impact callbacks")
	paused = true
	body.position += Vector3.UP
	await process_frame
	_expect(not watcher.is_physics_processing(), "Moving a frozen mount in planning does not activate impact checks")
	paused = false
	body.freeze = false
	WATCHER.wake(body)
	body.sleeping = false
	body.apply_central_impulse(Vector3.RIGHT)
	await _ticks(3)
	_expect(watcher.is_physics_processing(), "Existing wall-detachment wake command remains active")
	_sleep(body)
	await _ticks(3)
	stage.remove_child(body)
	body.freeze = false
	body.sleeping = false
	stage.add_child(body)
	watcher.reset_fragment()
	_expect(watcher.is_physics_processing() and is_equal_approx(watcher._quiet, 0.4), "Reused fragment resets its watcher and sound cooldown")
	body.free()
	await process_frame
	# Initially sleeping bodies also need the non-signal wake path.
	body = _body(Vector3(0, 3, 0))
	await _ticks(2)
	_sleep(body)
	body.get_node("ImpactSound").free()
	WATCHER.watch(body)
	var initial := body.get_node("ImpactSound")
	_expect(not initial.is_physics_processing(), "Already sleeping furniture starts without callbacks")
	body.sleeping = false
	body.apply_central_impulse(Vector3.RIGHT)
	await _ticks(4)
	_expect(initial.is_physics_processing(), "Initially sleeping furniture resumes after a scripted impulse")
	body.free()
	await process_frame


func _fall_again() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.5
	var shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 1, 20)
	shape.shape = floor_box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	var body := _body(Vector3(0, 4, 0), 1.0)
	_expect(await _heard_landing(), "First real landing plays its impact sound")
	_sleep(body)
	await _ticks(3)
	_expect(not body.get_node("ImpactSound").is_physics_processing(), "Landing followed by prepared sleep stops watching")
	for voice in get_nodes_in_group(&"sfx_fall_metal"):
		voice.queue_free()
	await process_frame
	body.position = Vector3(0, 4, 0)
	body.sleeping = false
	body.apply_central_impulse(Vector3.DOWN)
	_expect(await _heard_landing(), "Landing after a scripted wake still plays its impact sound")
	body.free()
	floor_body.free()
	await process_frame


func _heard_landing() -> bool:
	for tick in 150:
		await _ticks(1)
		if get_node_count_in_group(&"sfx_fall_metal") > 0:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
