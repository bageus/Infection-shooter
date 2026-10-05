extends SceneTree
## Runtime checks for enemy animation (ADR-0015, ADR-0016): authored clip
## sets for every enemy, stalk/charge locomotion, reaching run, wind-up
## attacks, death, far-enemy pausing, the Colossus slam wave and the Horde's
## ram and summoning pulse.

const ZOMBIE := preload("res://game/features/infected/public/infected_capsule.tscn")
const MUTANT := preload("res://game/features/infected/public/mutant_level2.tscn")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const COLOSSUS := preload("res://game/features/infected/public/infected_colossus.tscn")
const HORDE := preload("res://game/features/infected/public/infected_horde.tscn")
const HUMANOIDS := [
	"res://game/features/infected/public/infected_capsule.tscn",
	"res://game/features/infected/public/mutant_level2.tscn",
	"res://game/features/infected/public/infected_hunger.tscn",
	"res://game/features/infected/public/infected_revenant.tscn",
	"res://game/features/infected/public/infected_brute.tscn",
	"res://game/features/infected/public/infected_titan.tscn",
	"res://game/features/infected/public/infected_colossus.tscn",
]

class FakeTarget:
	extends Node3D
	var damage_taken := 0.0
	func take_damage(amount: float, _kind: String = "physical") -> void:
		damage_taken += amount

class FakePlayer:
	extends StaticBody3D
	var damage_taken := 0.0
	func take_damage(amount: float, _kind: String = "physical") -> void:
		damage_taken += amount

class FakeProp:
	extends StaticBody3D
	var hits := 0
	func take_projectile_hit(_damage: float, _position: Vector3, _normal: Vector3, _direction: Vector3, weapon: String) -> bool:
		if weapon == "GRENADE":
			hits += 1
		return true

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	_add_floor(stage)
	for path: String in HUMANOIDS:
		await _test_humanoid_clips(stage, load(path) as PackedScene, path.get_file())
	await _test_horde_clips(stage)
	await _test_locomotion_selection(stage, ZOMBIE, "Zombie")
	await _test_locomotion_selection(stage, HUNGER, "Hunger")
	await _test_one_shots(stage)
	await _test_skinned_rig(stage)
	await _test_stalk_then_charge(stage)
	await _test_attack_lands_on_hit_frame(stage)
	await _test_attack_misses_when_target_leaves(stage)
	await _test_death_animation_then_sink(stage)
	await _test_far_enemy_pauses_animation(stage)
	await _test_colossus_slam(stage)
	await _test_horde_ram(stage)
	await _test_horde_summon(stage)
	stage.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Enemy animation tests: %d failure(s)." % failures)
	quit(failures)


func _add_floor(stage: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)


func _spawn(stage: Node3D, scene: PackedScene, at := Vector3(0, 1.0, 0)) -> CharacterBody3D:
	var enemy := scene.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = at
	await process_frame
	return enemy


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _physics(count: int) -> void:
	for i in count:
		await physics_frame


func _player_of(enemy: Node) -> AnimationPlayer:
	return enemy.get_node("AnimationDriver").get("animation_player") as AnimationPlayer


# Samples a clip and returns skeleton-space bone positions (model +Z is front).
func _pose(player: AnimationPlayer, clip: String, time: float, bones: Array) -> Dictionary:
	player.play(clip)
	player.seek(time, true)
	player.advance(0.0)
	var skeleton := player.get_parent().find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var result := {}
	for bone: String in bones:
		result[bone] = skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	return result


func _test_humanoid_clips(stage: Node3D, scene: PackedScene, label: String) -> void:
	var enemy := await _spawn(stage, scene)
	var player := _player_of(enemy)
	_expect(player != null, label + " has an AnimationPlayer.")
	if player == null:
		enemy.queue_free()
		return
	for clip in ["Idle", "Walk", "Run"]:
		_expect(player.has_animation(clip) and player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "%s %s exists and loops." % [label, clip])
	for clip in ["AttackLeft", "AttackRight", "Death"]:
		_expect(player.has_animation(clip) and player.get_animation(clip).loop_mode == Animation.LOOP_NONE, "%s %s exists and is one-shot." % [label, clip])
	enemy.get_node("AnimationDriver").set_process(false)
	var bones := ["Chest", "Head", "L_Hand", "R_Hand", "L_Foot", "R_Foot", "Hips"]
	var idle := _pose(player, "Idle", 0.0, bones)
	var height: float = (idle["Head"] as Vector3).y - minf((idle["L_Foot"] as Vector3).y, (idle["R_Foot"] as Vector3).y)
	# Running: both hands reach out in front of the chest, the torso leans in.
	var run_length := player.get_animation("Run").length
	var reach_ok := true
	var feet_swap := []
	for i in 4:
		var run := _pose(player, "Run", run_length * float(i) / 4.0, bones)
		var chest: Vector3 = run["Chest"]
		for hand in ["L_Hand", "R_Hand"]:
			if (run[hand] as Vector3).z < chest.z + 0.18 * height:
				reach_ok = false
		feet_swap.append(signf((run["L_Foot"] as Vector3).z - (run["R_Foot"] as Vector3).z))
	_expect(reach_ok, label + " runs reaching forward with both hands.")
	_expect(feet_swap.has(1.0) and feet_swap.has(-1.0), label + " run alternates the legs.")
	var walk_length := player.get_animation("Walk").length
	var walk_a := _pose(player, "Walk", walk_length * 0.25, bones)
	var walk_b := _pose(player, "Walk", walk_length * 0.75, bones)
	var lead_a := (walk_a["L_Foot"] as Vector3).z - (walk_a["R_Foot"] as Vector3).z
	var lead_b := (walk_b["L_Foot"] as Vector3).z - (walk_b["R_Foot"] as Vector3).z
	_expect(lead_a * lead_b < 0.0 and absf(lead_a) > 0.12 * height, label + " walk steps with each leg in turn (not a limp).")
	# Attacks wind up above the head before striking forward.
	var attack_length := player.get_animation("AttackRight").length
	var windup := _pose(player, "AttackRight", attack_length * 0.38, bones)
	_expect((windup["R_Hand"] as Vector3).y > (windup["Head"] as Vector3).y, label + " AttackRight winds the arm up above the head.")
	var strike := _pose(player, "AttackRight", attack_length * 0.47, bones)
	_expect((strike["R_Hand"] as Vector3).z > (strike["Chest"] as Vector3).z + 0.2 * height, label + " AttackRight strikes forward at the hit frame.")
	var left := _pose(player, "AttackLeft", attack_length * 0.38, bones)
	_expect((left["L_Hand"] as Vector3).y > (left["Head"] as Vector3).y, label + " AttackLeft mirrors the wind-up.")
	var death := _pose(player, "Death", player.get_animation("Death").length, bones)
	_expect((death["Head"] as Vector3).y - (death["L_Foot"] as Vector3).y < 0.3 * height, label + " Death ends lying on the floor.")
	enemy.queue_free()
	await process_frame


func _test_horde_clips(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HORDE)
	var player := _player_of(enemy)
	_expect(player != null, "Horde has an AnimationPlayer.")
	if player != null:
		for clip in ["Idle", "Walk", "Run", "Summon", "Death"]:
			_expect(player.has_animation(clip), "Horde has " + clip)
		_expect(not player.has_animation("AttackLeft") and not player.has_animation("AttackRight"), "Horde has no swipe clip: it rams.")
	enemy.queue_free()
	await process_frame


func _test_locomotion_selection(stage: Node3D, scene: PackedScene, label: String) -> void:
	var enemy := await _spawn(stage, scene)
	enemy.set_physics_process(false)
	var driver := enemy.get_node("AnimationDriver")
	var player := _player_of(enemy)
	await _frames(3)
	_expect(player.current_animation == "Idle", label + " stands in Idle.")
	enemy.velocity = Vector3(0, 0, float(driver.get("walk_reference_speed")))
	await _frames(3)
	_expect(player.current_animation == "Walk", label + " stalking speed plays Walk.")
	_expect(absf(player.speed_scale - 1.0) < 0.05, label + " Walk is paced for its speed.")
	enemy.velocity = Vector3(0, 0, float(driver.get("run_reference_speed")))
	await _frames(3)
	_expect(player.current_animation == "Run", label + " charging speed plays Run.")
	_expect(absf(player.speed_scale - 1.0) < 0.05, label + " Run is paced for its speed.")
	enemy.velocity = Vector3.ZERO
	await _frames(3)
	_expect(player.current_animation == "Idle", label + " returns to Idle.")
	enemy.queue_free()
	await process_frame


func _test_one_shots(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	var driver := enemy.get_node("AnimationDriver")
	var player := _player_of(enemy)
	var finished: Array[StringName] = []
	driver.connect("one_shot_finished", func(state: StringName) -> void: finished.append(state))
	var first := float(driver.call("play_one_shot", &"attack"))
	_expect(first > 0.5, "Attack returns its clip length.")
	var first_clip := player.current_animation
	await create_timer(first + 0.1).timeout
	_expect(finished.has(&"attack"), "Attack reports completion.")
	driver.call("play_one_shot", &"attack")
	_expect(player.current_animation != first_clip, "Consecutive attacks alternate left and right.")
	_expect(float(driver.call("play_one_shot", &"slam")) == 0.0, "Enemies without a slam clip ignore slam.")
	await create_timer(first + 0.1).timeout
	var death := float(driver.call("play_one_shot", &"death"))
	_expect(death > 1.0 and player.current_animation == "Death", "Death plays the Death clip.")
	_expect(float(driver.call("play_one_shot", &"attack")) == 0.0, "Death is final.")
	enemy.velocity = Vector3(0, 0, 4.5)
	await create_timer(death + 0.2).timeout
	_expect(player.assigned_animation == "Death", "Locomotion never overrides a finished death pose.")
	enemy.queue_free()
	await process_frame


func _test_skinned_rig(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	var meshes := enemy.get_node("Body").find_children("*", "MeshInstance3D", true, false)
	_expect(meshes.size() == 1, "Hunger has one skinned mesh.")
	if meshes.size() == 1:
		var mesh := meshes[0] as MeshInstance3D
		_expect(mesh.skin != null and mesh.skin.get_bind_count() == 22, "Hunger mesh is bound to its 22-bone skeleton.")
		var triangles: int = (mesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
		_expect(triangles <= 10000, "Hunger stays within the crowd budget (%d triangles)." % triangles)
		_expect(mesh.get_surface_override_material(0) != null, "Hunger keeps its material.")
	enemy.queue_free()
	await process_frame


func _test_stalk_then_charge(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, -20)
	enemy.call("set_target", target)
	await _physics(10)
	var move_speed := float(enemy.get("move_speed"))
	var far_speed := Vector2(enemy.velocity.x, enemy.velocity.z).length()
	_expect(absf(far_speed - move_speed * float(enemy.get("walk_speed_factor"))) < 0.05, "A distant enemy stalks at walking speed (%.2f)." % far_speed)
	target.global_position = enemy.global_position + Vector3(0, 0, -6)
	await _physics(10)
	var near_speed := Vector2(enemy.velocity.x, enemy.velocity.z).length()
	_expect(absf(near_speed - move_speed) < 0.05, "A close enemy charges at full speed (%.2f)." % near_speed)
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_attack_lands_on_hit_frame(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, 1.0)
	enemy.call("set_target", target)
	await physics_frame
	await physics_frame
	_expect(target.damage_taken == 0.0, "Damage is not instant: the blow lands after the wind-up.")
	var length := _player_of(enemy).get_animation("AttackRight").length
	await create_timer(length * 0.45 + 0.08).timeout
	_expect(is_equal_approx(target.damage_taken, 12.0), "The blow lands once at the strike (got %s)." % target.damage_taken)
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_attack_misses_when_target_leaves(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, 1.0)
	enemy.call("set_target", target)
	await physics_frame
	await physics_frame
	target.global_position = enemy.global_position + Vector3(0, 0, 4.0)
	await create_timer(0.6).timeout
	_expect(target.damage_taken == 0.0, "The blow misses when the target left reach during the wind-up.")
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_death_animation_then_sink(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	enemy.set("death_linger_seconds", 0.1)
	var body := enemy.get_node("Body") as Node3D
	var start_y := body.position.y
	var length := _player_of(enemy).get_animation("Death").length
	enemy.call("take_damage", 1000.0)
	await create_timer(length * 0.5).timeout
	_expect(body.visible and is_equal_approx(body.position.y, start_y), "The corpse stays while the death animation plays.")
	await create_timer(length * 0.5 + 0.45).timeout
	_expect(body.visible and body.position.y < start_y, "The corpse sinks after the animation.")
	await create_timer(0.9).timeout
	_expect(not body.visible, "The corpse is hidden after sinking.")
	enemy.queue_free()
	await process_frame


func _test_far_enemy_pauses_animation(stage: Node3D) -> void:
	var enemy := await _spawn(stage, ZOMBIE)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(60, 0, 0)
	enemy.call("set_target", target)
	var player := _player_of(enemy)
	await physics_frame
	await physics_frame
	_expect(not player.active, "Far enemies stop animating.")
	target.global_position = enemy.global_position + Vector3(6, 0, 0)
	await physics_frame
	await physics_frame
	_expect(player.active, "Enemies animate again when the player approaches.")
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_colossus_slam(stage: Node3D) -> void:
	var enemy := await _spawn(stage, COLOSSUS, Vector3(30, 1.5, 0))
	enemy.set("_slam_cooldown", 0.0)
	var target := FakePlayer.new()
	target.add_to_group("player")
	var body_shape := CollisionShape3D.new()
	body_shape.shape = CapsuleShape3D.new()
	target.add_child(body_shape)
	stage.add_child(target)
	var prop := FakeProp.new()
	var prop_shape := CollisionShape3D.new()
	prop_shape.shape = BoxShape3D.new()
	prop.add_child(prop_shape)
	stage.add_child(prop)
	prop.global_position = enemy.global_position + Vector3(2.5, -1.0, 2.0)
	var crate := RigidBody3D.new()
	crate.collision_mask = 3
	var crate_shape := CollisionShape3D.new()
	crate_shape.shape = BoxShape3D.new()
	crate.add_child(crate_shape)
	stage.add_child(crate)
	crate.global_position = enemy.global_position + Vector3(-2.5, -1.0, -1.5)
	var ally := await _spawn(stage, ZOMBIE, enemy.global_position + Vector3(-2.0, -0.5, 1.5))
	ally.set_physics_process(false)
	target.global_position = enemy.global_position + Vector3(0, -0.5, -3.0)
	enemy.call("set_target", target)
	await physics_frame
	await physics_frame
	var player := _player_of(enemy)
	_expect(player.current_animation == "Slam", "Colossus slams when the player is close.")
	var slam := player.get_animation("Slam").length
	await create_timer(slam * 0.5).timeout
	_expect(prop.hits == 0, "Nothing breaks before the fists hit the floor.")
	var crate_start := crate.global_position
	await create_timer(slam * 0.06 + 0.8).timeout
	_expect(crate.global_position.distance_to(crate_start) > 0.3, "The slam wave throws loose objects outward.")
	_expect(prop.hits == 1, "The slam wave hits breakable objects around it once.")
	_expect(target.damage_taken > 0.0, "The slam wave hurts the player.")
	_expect(float(ally.get("health")) == float(ally.get("max_health")), "The slam wave spares other infected.")
	enemy.queue_free()
	target.queue_free()
	prop.queue_free()
	crate.queue_free()
	ally.queue_free()
	await process_frame


func _test_horde_ram(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HORDE, Vector3(-30, 1.0, 0))
	enemy.set("_summon_cooldown", 99.0)
	enemy.set("_ram_cooldown", 0.0)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, -6.0)
	enemy.call("set_target", target)
	await physics_frame
	await physics_frame
	_expect(int(enemy.get("state")) == 1, "Horde braces before ramming.")
	var top_speed := 0.0
	for i in 150:
		await physics_frame
		top_speed = maxf(top_speed, Vector2(enemy.velocity.x, enemy.velocity.z).length())
		if target.damage_taken > 0.0:
			break
	_expect(top_speed > 7.0, "Horde accelerates into a ram (%.1f m/s)." % top_speed)
	_expect(is_equal_approx(target.damage_taken, float(enemy.get("attack_damage"))), "The ram hits once (got %s)." % target.damage_taken)
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_horde_summon(stage: Node3D) -> void:
	var holder := Node3D.new()
	stage.add_child(holder)
	var enemy := HORDE.instantiate() as CharacterBody3D
	holder.add_child(enemy)
	enemy.global_position = Vector3(-30, 1.0, 30)
	await process_frame
	enemy.set("_summon_cooldown", 0.0)
	enemy.set("_ram_cooldown", 99.0)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, -15.0)
	enemy.call("set_target", target)
	await physics_frame
	await physics_frame
	var player := _player_of(enemy)
	_expect(player.current_animation == "Summon", "Horde plays its summoning pulse.")
	var before := holder.get_child_count()
	await create_timer(player.get_animation("Summon").length * 0.45 + 0.2).timeout
	var summoned := 0
	for child in holder.get_children():
		if child.has_meta("summoned_by"):
			summoned += 1
	_expect(summoned == int(enemy.get("summon_count")), "The pulse calls %d infected (got %d)." % [int(enemy.get("summon_count")), summoned])
	_expect(holder.get_child_count() > before, "Summoned infected join the Horde's parent.")
	enemy.queue_free()
	target.queue_free()
	holder.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
