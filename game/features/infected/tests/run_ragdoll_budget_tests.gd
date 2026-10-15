extends SceneTree
## A01: slots count running physics, while retained corpses keep their last pose.
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const BUDGET := preload("res://game/features/infected/public/corpse_budget.gd")
const RAGDOLL := preload("res://game/features/infected/death_ragdoll.gd")
var failures := 0
var stage: Node3D
var next_position := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(400, 1, 400)
	floor_body.add_child(shape)
	floor_body.position.y = -.5
	stage.add_child(floor_body)
	await _test_pose_transfer(Vector3.ONE)
	await _test_pose_transfer(Vector3.ONE * 1.2)
	await _test_retained_waves()
	await _test_eviction()
	await _test_burst_and_early_free()
	await _test_sink_releases_slot()
	await _clear()
	BUDGET.keep = false
	stage.queue_free()
	await process_frame
	print("Ragdoll budget tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _test_pose_transfer(size: Vector3) -> void:
	BUDGET.keep = true
	var enemy := await _spawn(30.0, size)
	_kill(enemy)
	var physics: RefCounted = enemy.get("_ragdoll")
	var skeleton: Skeleton3D = physics.get("skeleton")
	var simulator: PhysicalBoneSimulator3D = physics.get("simulator")
	await create_timer(.5).timeout
	# Include a removed limb: its pending deletion must not restore its pose.
	enemy.get("_parts").call("sever", &"arm_l", Vector3.ZERO, false)
	await process_frame
	var expected: Dictionary = {}
	for bone: PhysicalBone3D in simulator.get_children():
		expected[bone.get_bone_id()] = skeleton.global_transform.affine_inverse() * bone.global_transform * bone.body_offset.affine_inverse()
	physics.call("freeze_pose")
	_expect(not simulator.active, "Pose transfer stops the simulator.")
	for bone: PhysicalBone3D in simulator.get_children():
		_expect(not bone.is_simulating_physics(), "Retained bones leave physical simulation.")
	# Observe the rendered skeleton after modifier processing, over several frames.
	var sample: Dictionary = {}
	var capture := func() -> void:
		for index: int in expected:
			sample[index] = skeleton.get_bone_global_pose(index)
	skeleton.skeleton_updated.connect(capture)
	for frame in 4:
		await process_frame
		capture.call()
		for index: int in expected:
			var actual: Transform3D = sample[index]
			var wanted: Transform3D = expected[index]
			_expect(actual.origin.distance_to(wanted.origin) < .001, "Frozen %s position persists at scale %s." % [skeleton.get_bone_name(index), size])
			_expect(actual.basis.is_equal_approx(wanted.basis), "Frozen bone orientation and scale persist.")
	skeleton.skeleton_updated.disconnect(capture)
	await _clear()


func _test_retained_waves() -> void:
	BUDGET.keep = true
	for index in RAGDOLL.MAX_ACTIVE + 2:
		var enemy := await _spawn(.03)
		_kill(enemy)
		_expect(enemy.get("_ragdoll") != null, "Later waves can reuse a stopped corpse's slot.")
		await create_timer(.08).timeout
		_expect(_running_count() == RAGDOLL._active, "Slot count equals actual running simulators.")
		_expect(_running_count() <= RAGDOLL.MAX_ACTIVE, "Actual physics stays within the cap.")
	_expect(BUDGET.count() == 10, "Ten corpses stay retained across waves.")
	_expect(_running_count() == 0, "Retained corpses stop simulating after linger.")
	for enemy: Node in stage.get_children():
		if enemy is CharacterBody3D:
			_expect((enemy.get("body_visual") as Node3D).visible, "Stopped corpses remain visible.")
	await _clear()


func _test_eviction() -> void:
	BUDGET.keep = true
	var enemy := await _spawn(.03)
	_kill(enemy)
	await create_timer(.08).timeout
	var fillers: Array[Node] = []
	for index in BUDGET.MAX_CORPSES:
		var owner := Node.new()
		stage.add_child(owner)
		fillers.append(owner)
		BUDGET.retain(owner, null, func() -> void: pass)
	_expect(BUDGET.count() == BUDGET.MAX_CORPSES, "Overflow keeps the sixty-body budget.")
	_expect(not (enemy.get("body_visual") as Node3D).visible, "Overflow hides the oldest retained real corpse.")
	_expect(RAGDOLL._active == 0, "Evicting stopped physics does not decrement another slot.")
	for owner in fillers:
		owner.queue_free()
	await _clear()


func _test_burst_and_early_free() -> void:
	BUDGET.keep = true
	var enemies: Array[CharacterBody3D] = []
	for index in RAGDOLL.MAX_ACTIVE + 1:
		enemies.append(await _spawn(30.0))
	for enemy in enemies:
		_kill(enemy)
	_expect(_running_count() == RAGDOLL.MAX_ACTIVE, "Burst fills exactly eight simulators.")
	_expect(enemies.back().get("_ragdoll") == null, "Ninth simultaneous death uses the clip fallback.")
	enemies.front().queue_free()
	await process_frame
	_expect(RAGDOLL._active == RAGDOLL.MAX_ACTIVE - 1, "Early deletion releases exactly one slot.")
	var replacement := await _spawn(30.0)
	_kill(replacement)
	_expect(replacement.get("_ragdoll") != null, "A new death reuses the early-deletion slot.")
	_expect(_running_count() == RAGDOLL._active, "Burst accounting matches physics after reuse.")
	await _clear()


func _test_sink_releases_slot() -> void:
	BUDGET.keep = false
	var enemy := await _spawn(.03)
	_kill(enemy)
	await create_timer(.08).timeout
	_expect(RAGDOLL._active == 1, "Sinking physics still owns its slot.")
	await create_timer(RAGDOLL.SINK_SECONDS + .1).timeout
	_expect(is_instance_valid(enemy), "Cloud lifetime has not removed the owner yet.")
	_expect(not (enemy.get("body_visual") as Node3D).visible, "Timed corpse hides after sinking.")
	_expect(_running_count() == 0 and RAGDOLL._active == 0, "Hidden corpse releases its slot before cloud teardown.")
	await _clear()


func _spawn(linger: float, size: Vector3 = Vector3.ONE) -> CharacterBody3D:
	var enemy := HUNGER.instantiate() as CharacterBody3D
	enemy.position = Vector3(next_position * 4 - 100, 1, 0)
	enemy.scale = size
	next_position += 1
	enemy.set("death_linger_seconds", linger)
	stage.add_child(enemy)
	enemy.set_physics_process(false)
	await physics_frame
	return enemy


func _kill(enemy: CharacterBody3D) -> void:
	enemy.call("take_projectile_damage", 1000.0, enemy.global_position, Vector3.FORWARD, "PISTOL")


func _running_count() -> int:
	var count := 0
	for simulator: PhysicalBoneSimulator3D in stage.find_children("CorpsePhysics", "PhysicalBoneSimulator3D", true, false):
		if simulator.active:
			count += 1
	return count


func _clear() -> void:
	for child in stage.get_children():
		if child is CharacterBody3D:
			child.queue_free()
	await process_frame
	await process_frame
	_expect(RAGDOLL._active == 0 and RAGDOLL._slots.is_empty(), "Teardown releases all slots without double decrement.")
	_expect(BUDGET.count() == 0, "Teardown prunes the retained body budget.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
