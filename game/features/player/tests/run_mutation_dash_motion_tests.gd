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
	_test_effect_recovery(player)
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


func _test_effect_recovery(player: CharacterBody3D) -> void:
	var runtime: Node = player.get("infection_runtime")
	var effects: Node = player.get("mutation_effects")
	runtime.get("_domain").mutation = 94.0
	runtime.get("_domain").critical_threshold = 95.0
	runtime.call("upgrade_skill", "active_claws")
	runtime.call("toggle_skill_lock", "active_claws")
	_expect(runtime.call("cast_skill", "active_claws"), "Real player can cast the auto-equipped Claws")
	_expect(runtime.call("skill_effect_remaining", "active_claws") == 2.5 and runtime.call("skill_cooldown_remaining", "active_claws") == 0.0, "Real effect reports its duration before recovery")
	for frame in 2:
		effects.call("_process", 1.25)
		runtime.call("_physics_process", 1.25)
	_expect(effects.get("_active_effects").running.is_empty() and runtime.call("skill_cooldown_remaining", "active_claws") == 5.0, "Recovery begins when actual Claws damage window ends")
	runtime.call("reduce_skill_cooldowns", 5.0)
	runtime.call("cast_skill", "active_claws")
	runtime.get("_domain").mutation = 10.0
	runtime.call("_emit_state_changes", 94.0)
	_expect(effects.get("_active_effects").running.is_empty() and runtime.call("skill_effect_remaining", "active_claws") == 0.0, "Dormancy cancels the active aura instead of leaving a latent effect timer")
	runtime.get("_domain").mutation = 94.0
	runtime.call("_emit_state_changes", 10.0)
	runtime.call("reduce_skill_cooldowns", 5.0)
	_expect(runtime.call("can_cast_skill", "active_claws"), "Full reactivation cooldown restores readiness without an extra stale aura duration")
