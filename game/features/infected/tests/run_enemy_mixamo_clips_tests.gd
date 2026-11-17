extends SceneTree
## The owner's Mixamo set on Hunger, Revenant, Brute, Colossus and Titan (ADR-0071): which clips
## each enemy has, random idles, the stop transition, the wander walk, attack and death picks,
## the hit clip for heavy weapons only, turns on the spot and the climb out of a spawn hole.

const DIR := "res://game/features/infected/public/"
const ALL := ["hunger", "revenant", "brute", "colossus", "titan"]
const HEAVY := ["revenant", "brute", "colossus", "titan"]
# Clips per enemy that must exist on top of the model's own; looping ones loop.
const COMMON := ["Transition", "IdleZombie1", "IdleZombie2", "IdleZombie3", "IdleZombie4", "IdleOrc", "IdleOldMan", "DeathSide", "DeathSide2", "DeathForward", "DeathBack", "Climb"]
const BIG_IDLES := ["IdleMutant", "IdleScratch"]
const HEAVY_ONLY := ["HitReaction", "TurnLeft", "TurnRight"]
const LEFT_ATTACKS := {"revenant": 1, "brute": 4, "colossus": 4, "titan": 4}
const RIGHT_ATTACKS := {"revenant": 1, "brute": 1, "colossus": 4, "titan": 4}

class FakeTarget:
	extends Node3D
	func take_damage(_amount: float, _kind: String = "physical") -> void:
		pass

var failures := 0
var stage: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)
	for name: String in ALL:
		await _test_seams(name)
		await _test_clip_set(name)
		await _test_death_picks(name)
	for name: String in HEAVY:
		await _test_attack_variants(name)
		await _test_hit_clip(name)
		await _test_turn_in_place(name)
	await _test_idle_pool("brute")
	await _test_idle_pool("hunger")
	await _test_wander_walk_and_transition("brute")
	await _test_wander_walk_and_transition("revenant")
	await _test_climb_out("titan")
	await _test_climb_out("hunger")
	stage.queue_free()
	await process_frame
	print("Enemy Mixamo clip tests: %d failure(s)." % failures)
	quit(failures)


func _spawn(name: String, at := Vector3(0, 1.2, 0)) -> CharacterBody3D:
	var enemy := (load(DIR + "infected_%s.tscn" % name) as PackedScene).instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = at
	enemy.set_physics_process(false)
	await process_frame
	return enemy


func _player_of(enemy: Node) -> AnimationPlayer:
	return enemy.get_node("AnimationDriver").get("animation_player") as AnimationPlayer


func _test_clip_set(name: String) -> void:
	var enemy := await _spawn(name)
	var player := _player_of(enemy)
	var wanted: Array = COMMON.duplicate()
	if name in ["colossus", "titan"]:
		wanted.append_array(BIG_IDLES)
	if name in HEAVY:
		wanted.append_array(HEAVY_ONLY)
	if name in ["brute", "colossus", "titan", "revenant"]:
		wanted.append("WalkWander")
	for clip: String in wanted:
		_expect(player.has_animation(clip), "%s has %s." % [name, clip])
	for clip in ["IdleZombie1", "IdleOrc", "IdleOldMan"]:
		_expect(player.has_animation(clip) and player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "%s %s loops." % [name, clip])
	for clip in ["Transition", "DeathSide", "DeathForward", "DeathBack", "Climb"]:
		_expect(player.has_animation(clip) and player.get_animation(clip).loop_mode == Animation.LOOP_NONE, "%s %s plays once." % [name, clip])
	if name != "hunger" and player.has_animation("WalkWander"):
		_expect(float(player.get_animation("WalkWander").get_meta("ref_speed", 0.0)) > 0.0 and bool(player.get_animation("WalkWander").get_meta("own_pace", false)), name + " WalkWander is paced by its own ground speed.")
	if name in LEFT_ATTACKS:
		var suffixes := ["", "2", "3", "4"]
		for index in int(LEFT_ATTACKS[name]):
			_expect(player.has_animation("AttackLeft" + suffixes[index]), "%s has AttackLeft%s." % [name, suffixes[index]])
		for index in int(RIGHT_ATTACKS[name]):
			_expect(player.has_animation("AttackRight" + suffixes[index]), "%s has AttackRight%s." % [name, suffixes[index]])
		_expect(float(player.get_animation("AttackLeft").get_meta("strike_time", 0.0)) > 0.0, name + " AttackLeft names its strike time.")
	if name == "hunger":
		_expect(player.get_animation("TurnLeft2").get_meta("yaw_curve", PackedFloat32Array()).size() > 1, "Hunger TurnLeft2 carries its yaw curve.")
	enemy.queue_free()
	await process_frame


# Seams between clips: a cycle ends where it starts, the transition into idle ends over its start (no
# slide), and the game cross-fades the added clips longer than plain locomotion.
func _test_seams(name: String) -> void:
	var enemy := await _spawn(name)
	var player := _player_of(enemy)
	var skeleton := enemy.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	enemy.get_node("AnimationDriver").set_process(false)
	var idle := _pose(player, skeleton, "Idle", 0.0)
	var height: float = (idle["Head"] as Vector3).y - (idle["L_Foot"] as Vector3).y
	for clip: String in player.get_animation_list():
		var animation := player.get_animation(clip)
		if animation.loop_mode == Animation.LOOP_LINEAR and clip.begins_with("Idle") or clip.begins_with("Walk") or clip.begins_with("Run"):
			var first := _pose(player, skeleton, clip, 0.0)
			var last := _pose(player, skeleton, clip, animation.length)
			_expect(_apart(first, last) < 0.08 * height, "%s %s loops without a jump (%.2f)." % [name, clip, _apart(first, last) / height])
	var begin := _pose(player, skeleton, "Transition", 0.0)
	var end := _pose(player, skeleton, "Transition", player.get_animation("Transition").length)
	var drift := Vector2((end["Hips"] as Vector3).x - (begin["Hips"] as Vector3).x, (end["Hips"] as Vector3).z - (begin["Hips"] as Vector3).z).length()
	_expect(drift < 0.02 * height, "%s Transition ends over where it began (%.3f)." % [name, drift / height])
	var blends := preload("res://game/features/character_animation/public/enemy_blends.gd")
	_expect(blends.seconds("IdleOrc", 0.12) > 0.12 and blends.seconds("Run", 0.12) == 0.12 and blends.seconds("Run", 0.12, true) >= 0.3, name + " cross-fades added clips longer.")
	enemy.queue_free()
	await process_frame


func _pose(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, time: float) -> Dictionary:
	player.play(clip)
	player.seek(time, true)
	player.advance(0.0)
	var result := {}
	for bone in ["Hips", "Chest", "Head", "L_Hand", "R_Hand", "L_Foot", "R_Foot"]:
		result[bone] = skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	return result


func _apart(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for bone: String in a:
		worst = maxf(worst, (a[bone] as Vector3).distance_to(b[bone]))
	return worst


func _test_death_picks(name: String) -> void:
	var enemy := await _spawn(name)
	var driver := enemy.get_node("AnimationDriver")
	var player := _player_of(enemy)
	driver.call("play_one_shot", &"death_back")
	_expect(player.current_animation == "DeathBack", name + " thrown back plays DeathBack.")
	enemy.queue_free()
	await process_frame
	enemy = await _spawn(name)
	driver = enemy.get_node("AnimationDriver")
	player = _player_of(enemy)
	driver.call("play_one_shot", &"death_forward")
	_expect(player.current_animation == "DeathForward", name + " falling ahead plays DeathForward.")
	enemy.queue_free()
	await process_frame
	var sides := 0
	var runs := 40
	for index in runs:
		enemy = await _spawn(name)
		driver = enemy.get_node("AnimationDriver")
		driver.call("play_one_shot", &"death")
		if _player_of(enemy).current_animation.begins_with("DeathSide"):
			sides += 1
		enemy.queue_free()
	await process_frame
	_expect(sides > runs * 0.4 and sides < runs, "%s dies to the side more often from standing (%d of %d)." % [name, sides, runs])


func _test_attack_variants(name: String) -> void:
	var enemy := await _spawn(name)
	var driver := enemy.get_node("AnimationDriver")
	var seen := {}
	for index in 60:
		driver.set("_one_shot", &"")
		driver.call("play_one_shot", &"attack_left")
		seen[_player_of(enemy).current_animation] = true
		driver.set("_one_shot", &"")
		driver.call("play_one_shot", &"attack_right")
		seen[_player_of(enemy).current_animation] = true
	var expected: int = int(LEFT_ATTACKS[name]) + int(RIGHT_ATTACKS[name])
	_expect(seen.size() == expected, "%s picks among %d attack clips (saw %s)." % [name, expected, str(seen.keys())])
	enemy.queue_free()
	await process_frame


func _test_hit_clip(name: String) -> void:
	var enemy := await _spawn(name)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = Vector3(0, 0.1, -12)
	enemy.call("set_target", target)
	enemy.set("max_health", 5000.0)
	enemy.set("health", 5000.0)
	await process_frame
	var point := enemy.global_position + Vector3(0, 0.5, -0.6)
	enemy.call("take_projectile_damage", 12.0, point, Vector3(0, 0, 1), "PISTOL")
	_expect(float(enemy.get("_hit_cooldown")) == 0.0, name + " ignores a pistol hit for the hit clip.")
	enemy.call("take_projectile_damage", 12.0, point, Vector3(0, 0, 1), "UZI")
	_expect(float(enemy.get("_hit_cooldown")) == 0.0, name + " ignores an Uzi hit for the hit clip.")
	enemy.call("take_projectile_damage", 40.0, point, Vector3(0, 0, 1), "SHOTGUN")
	_expect(float(enemy.get("_hit_cooldown")) > 0.0, name + " flinches with the hit clip from a shotgun.")
	enemy.set("_hit_cooldown", 0.0)
	enemy.call("take_blast_damage", 50.0, enemy.global_position + Vector3(2, 0, 0))
	_expect(float(enemy.get("_hit_cooldown")) > 0.0, name + " flinches with the hit clip from a blast.")
	enemy.set("_hit_cooldown", 0.0)
	enemy.set("health", 30.0)
	enemy.call("take_projectile_damage", 400.0, point, Vector3(0, 0, 1), "SHOTGUN")
	_expect(float(enemy.get("_hit_cooldown")) == 0.0, name + " does not flinch from the blow that kills it.")
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_turn_in_place(name: String) -> void:
	var enemy := await _spawn(name)
	var turn: RefCounted = enemy.get("_turn")
	var yaw := float(enemy.rotation.y)
	if name == "hunger":
		enemy.queue_free()
		return
	_expect(bool(turn.call("start", enemy.get_node("AnimationDriver"), yaw, Vector3(1, 0, 0.3).normalized())), name + " starts a turn for a big change of direction.")
	_expect(_player_of(enemy).current_animation.begins_with("TurnRight"), name + " turns right with a Turn clip (%s)." % _player_of(enemy).current_animation)
	var finished := yaw
	for step in 120:
		finished = float(turn.call("step", 1.0 / 30.0))
		if not bool(turn.call("active")):
			break
	var wanted := atan2(-0.9578, -0.2873)
	_expect(absf(wrapf(finished - wanted, -PI, PI)) < 0.05, "%s ends the turn facing the new direction." % name)
	_expect(not bool(turn.call("start", enemy.get_node("AnimationDriver"), wanted, Vector3(1, 0, 0.3).normalized())), name + " does not turn for a small change.")
	enemy.queue_free()
	await process_frame


func _test_idle_pool(name: String) -> void:
	var enemy := await _spawn(name)
	var driver := enemy.get_node("AnimationDriver")
	var pool: Array = driver.get("_variants").get("pool")
	_expect(pool.size() >= 7, "%s has the base idle and the added ones in its pool (%d)." % [name, pool.size()])
	var seen := {}
	for index in 80:
		driver.set("_current", "")
		driver.call("_process_skeletal", 0.0)
		seen[_player_of(enemy).current_animation] = true
	_expect(seen.size() >= 5, "%s starts different idles at random (%d seen)." % [name, seen.size()])
	enemy.queue_free()
	await process_frame


func _test_wander_walk_and_transition(name: String) -> void:
	var enemy := await _spawn(name)
	var driver := enemy.get_node("AnimationDriver")
	var player := _player_of(enemy)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = Vector3(0, 0.1, -30)
	enemy.call("watch_target", target)
	await process_frame
	enemy.velocity = Vector3(0, 0, 1.0)
	for index in 6:
		await process_frame
	_expect(player.current_animation == "WalkWander", name + " unaware and walking plays WalkWander (%s)." % player.current_animation)
	enemy.call("set_target", target)
	enemy.velocity = Vector3(0, 0, 1.0)
	for index in 6:
		await process_frame
	_expect(player.current_animation == "Walk", name + " chasing at a walking speed plays Walk (%s)." % player.current_animation)
	# Unaware again, walked long enough, then stopped: the transition into idle plays once.
	enemy.queue_free()
	target.queue_free()
	await process_frame
	var idler := await _spawn(name)
	var watched := FakeTarget.new()
	stage.add_child(watched)
	watched.global_position = Vector3(0, 0.1, -30)
	idler.call("watch_target", watched)
	var idle_player := _player_of(idler)
	idler.velocity = Vector3(0, 0, 1.0)
	await create_timer(1.0).timeout
	idler.velocity = Vector3.ZERO
	await create_timer(0.2).timeout
	_expect(idle_player.current_animation == "Transition", "%s stopping after a walk plays Transition (%s)." % [name, idle_player.current_animation])
	idler.velocity = Vector3(0, 0, 8.0)
	await create_timer(0.2).timeout
	_expect(idle_player.current_animation.begins_with("Run"), "%s running during Transition drops it for a run clip (%s)." % [name, idle_player.current_animation])
	idler.queue_free()
	watched.queue_free()
	await process_frame


func _test_climb_out(name: String) -> void:
	var enemy := (load(DIR + "infected_%s.tscn" % name) as PackedScene).instantiate() as CharacterBody3D
	enemy.set_meta(&"spawned_by", "hole")
	stage.add_child(enemy)
	enemy.global_position = Vector3(0, 1.2, 0)
	await process_frame
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = Vector3(0, 0.1, -20)
	enemy.call("set_target", target)
	var player := _player_of(enemy)
	_expect(player.current_animation == "Climb", name + " starts with the Climb clip (%s)." % player.current_animation)
	var start := enemy.global_position
	for index in 20:
		await physics_frame
	var horizontal := Vector2(enemy.global_position.x - start.x, enemy.global_position.z - start.z).length()
	_expect(horizontal < 0.05, name + " stands still while it climbs out.")
	await create_timer(float(player.get_animation("Climb").length) + 0.5).timeout
	await physics_frame
	await physics_frame
	_expect(Vector2(enemy.velocity.x, enemy.velocity.z).length() > 0.3, name + " chases once it is out.")
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
