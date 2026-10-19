extends SceneTree
## Hunger on the Mixamo clips (ADR-0045): postures, scream modes, turning,
## corpse feeding, the hit flinch and the mirrored left-hand attacks.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const BAKED_CORPSE := preload("res://game/features/infected/public/decor/corpse_zombie.tscn")
const CLIPS := preload("res://models/objects/characters/enemy/game/Hunger_mixamo.res")
const EXPECTED_CLIPS := [
	"Idle", "Walk", "Run", "RunLunge", "FoursRun", "FoursIdle", "Crawl", "CrawlIdle", "Scream", "Agonize",
	"TurnLeft", "TurnRight", "HitReaction", "AttackLeft", "AttackRight", "AttackLeft2", "AttackRight2",
	"BiteDown", "BiteLoop", "BiteUp", "DropToFours", "RiseFromFours", "CollapseToCrawl", "FoursToCrawl", "CrawlAttack",
]
const LOOPS := ["Idle", "Walk", "Run", "RunLunge", "FoursRun", "FoursIdle", "Crawl", "CrawlIdle", "BiteLoop"]
var failures := 0
var stage: Node3D


class Target:
	extends Node3D
	var damage := 0.0
	func take_damage(amount: float, _kind := "physical") -> void:
		damage += amount


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_clips()
	await _fresh_stage()
	await _crawl_after_leg()
	await _scream_modes()
	await _idle_scream_is_harmless()
	await _turn_in_place()
	await _feeding()
	await _baked_corpse_feeding()
	await _flinch()
	await _postures()
	await _crawl_attack()
	print("Hunger behaviour tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _fresh_stage() -> void:
	if stage != null:
		stage.queue_free()
		await process_frame
	stage = Node3D.new()
	root.add_child(stage)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	stage.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)


func _spawn(at: Vector3, player: Node3D = null) -> CharacterBody3D:
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = at
	if player != null:
		enemy.call("watch_target", player)
		enemy.get("_senses").wander_enabled = false
	return enemy


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _player_of(enemy: Node) -> AnimationPlayer:
	return enemy.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer


func _clips() -> void:
	for clip: String in EXPECTED_CLIPS:
		_check(CLIPS.has_animation(clip), "The Mixamo set has " + clip)
		if CLIPS.has_animation(clip):
			_check((CLIPS.get_animation(clip).loop_mode == Animation.LOOP_LINEAR) == (clip in LOOPS), "%s loops only when it is a cycle." % clip)
	for clip in ["Walk", "Run", "RunLunge", "FoursRun", "Crawl"]:
		_check(float(CLIPS.get_animation(clip).get_meta("ref_speed", 0.0)) > 0.0, clip + " names the speed it is paced for.")
	for clip in ["AttackLeft", "AttackRight", "AttackLeft2", "AttackRight2"]:
		_check(float(CLIPS.get_animation(clip).get_meta("strike_time", 0.0)) > 0.2, clip + " names its strike time.")
	_check(absf(float(CLIPS.get_animation("TurnRight").get_meta("turn_yaw")) + float(CLIPS.get_animation("TurnLeft").get_meta("turn_yaw"))) < 0.01, "The left turn mirrors the right turn.")
	_check(float(CLIPS.get_animation("TurnLeft").get_meta("turn_yaw")) > 1.0, "A left turn turns left (positive yaw) by more than 57 degrees.")
	# The left swing is the right one mirrored: the hips track is the same, the arms swap sides.
	var right := _hand_x(CLIPS.get_animation("AttackRight"), "R_Hand")
	var left := _hand_x(CLIPS.get_animation("AttackLeft"), "L_Hand")
	_check(right * left < 0.0 or absf(right + left) < 0.2, "The left-hand attack mirrors the right-hand one (%.2f vs %.2f)." % [right, left])
	# Transitions start where the cycle they leave ends and finish at the pose they enter.
	_check(_pose_gap("DropToFours", 0.0, "Idle", 0.0) < 0.02, "DropToFours starts in the idle pose.")
	_check(_pose_gap("DropToFours", CLIPS.get_animation("DropToFours").length, "FoursRun", 0.0) < 0.02, "DropToFours ends in the all-fours pose.")
	_check(_pose_gap("CollapseToCrawl", CLIPS.get_animation("CollapseToCrawl").length, "Crawl", 0.0) < 0.02, "CollapseToCrawl ends in the crawl pose.")


func _hand_x(animation: Animation, bone: String) -> float:
	for track in animation.get_track_count():
		if String(animation.track_get_path(track)).ends_with(":" + bone) and animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			return (Basis(animation.rotation_track_interpolate(track, animation.length * 0.4)) * Vector3.DOWN).x
	return 0.0


# Largest angle (rad) between the same bone in two clips at the given times.
func _pose_gap(a: String, a_time: float, b: String, b_time: float) -> float:
	var worst := 0.0
	var first := CLIPS.get_animation(a)
	var second := CLIPS.get_animation(b)
	for track in first.get_track_count():
		if first.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var other := second.find_track(first.track_get_path(track), Animation.TYPE_ROTATION_3D)
		worst = maxf(worst, first.rotation_track_interpolate(track, a_time).angle_to(second.rotation_track_interpolate(other, b_time)))
	return worst


func _crawl_after_leg() -> void:
	var enemy := _spawn(Vector3.ZERO)
	var player := _player_of(enemy)
	await _frames(3)
	_check(enemy.get("posture") == 0, "A fresh Hunger stands.")
	enemy.get("_parts").sever(&"leg_r", Vector3.RIGHT)
	await _frames(2)
	_check(enemy.get("posture") == 2, "A Hunger without a leg crawls on its belly.")
	_check(not bool(enemy.get("_dead")), "It survives the first leg.")
	_check(player.current_animation == "CollapseToCrawl", "It drops to the floor with the collapse clip (%s)." % player.current_animation)
	_check(is_equal_approx(float(enemy.get("_mobility")), 0.28), "Crawling is slow.")
	await create_timer(1.0).timeout
	enemy.velocity = Vector3(0, 0, 1.0)
	await _frames(3)
	_check(player.current_animation == "Crawl", "Moving, it plays the crawl cycle (%s)." % player.current_animation)
	enemy.velocity = Vector3.ZERO
	await _frames(3)
	_check(player.current_animation == "CrawlIdle", "Stopped, it lies still (%s)." % player.current_animation)
	_check(enemy.call("_attack_state") == &"attack_crawl", "A crawling Hunger claws instead of swinging.")
	enemy.queue_free()
	await process_frame


func _scream_modes() -> void:
	await _fresh_stage()
	var target := Target.new()
	stage.add_child(target)
	target.position = Vector3(0, 0.1, -6)
	var seer := _spawn(Vector3(0, 0.1, 0), target)
	var friend := _spawn(Vector3(3, 0.1, 2), target)
	friend.rotation.y = PI # facing away, outside its own sight cone, but within the cry
	await _frames(40)
	_check(seer.call("is_alerted"), "The Hunger that sees the player is alerted.")
	_check(_player_of(seer).current_animation == "Scream", "The first Hunger screams first (%s)." % _player_of(seer).current_animation)
	_check(friend.call("is_alerted"), "Its cry calls the neighbour.")
	var forced := _spawn(Vector3(-8, 0.1, 8))
	forced.call("set_target", target)
	await _frames(3)
	_check(not bool(forced.call("is_busy")), "A forced chase (spawner) does not scream.")
	_check(not bool(friend.call("is_busy")) or _player_of(friend).current_animation != "Scream", "The neighbour runs without screaming.")
	seer.queue_free()
	friend.queue_free()
	forced.queue_free()
	await process_frame


func _idle_scream_is_harmless() -> void:
	await _fresh_stage()
	var target := Target.new()
	stage.add_child(target)
	target.position = Vector3(0, 0.1, -40)
	var screamer := _spawn(Vector3(0, 0.1, 0), target)
	var friend := _spawn(Vector3(2, 0.1, 0), target)
	await _frames(3)
	screamer.call("_idle_flavor", true)
	await _frames(5)
	_check(_player_of(screamer).current_animation == "Scream", "An idle scream plays the Scream clip.")
	_check(not friend.call("is_alerted") and not screamer.call("is_alerted"), "An idle scream alerts nobody.")
	_check(bool(screamer.call("is_busy")), "The screamer holds still while it screams.")
	await create_timer(2.2).timeout
	_check(not bool(screamer.call("is_busy")), "The scream ends.")
	screamer.call("_idle_flavor", false)
	await _frames(3)
	_check(_player_of(screamer).current_animation == "Agonize", "The other idle flavour is the groan.")
	screamer.queue_free()
	friend.queue_free()
	await process_frame


func _turn_in_place() -> void:
	await _fresh_stage()
	var target := Target.new()
	stage.add_child(target)
	target.position = Vector3(0, 0.1, -40)
	var enemy := _spawn(Vector3(0, 0.1, 0), target)
	await _frames(3)
	enemy.set("_face_direction", Vector3(1, 0, 0.3).normalized())
	var yaw := float(enemy.rotation.y)
	var wanted := atan2(-enemy.get("_face_direction").x, -enemy.get("_face_direction").z)
	_check(bool(enemy.call("_start_turn_if_needed", yaw)), "A big change of direction starts a turn.")
	_check(_player_of(enemy).current_animation == "TurnRight", "Turning toward its right plays TurnRight (%s)." % _player_of(enemy).current_animation)
	await create_timer(0.3).timeout
	var partway := wrapf(enemy.rotation.y - yaw, -PI, PI)
	await create_timer(2.0).timeout
	var done := wrapf(enemy.rotation.y - wanted, -PI, PI)
	_check(absf(done) < 0.05, "The turn ends facing the new direction (off by %.2f rad)." % done)
	_check(absf(partway) < absf(wrapf(wanted - yaw, -PI, PI)) - 0.1, "The body turns with the clip, not at once.")
	enemy.set("_face_direction", Vector3(0.95, 0, 0.4).normalized())
	_check(not bool(enemy.call("_start_turn_if_needed", enemy.rotation.y)), "A small correction needs no turn clip.")
	enemy.queue_free()
	await process_frame


func _feeding() -> void:
	await _fresh_stage()
	var target := Target.new()
	stage.add_child(target)
	target.position = Vector3(0, 0.1, -40)
	var victim := _spawn(Vector3(1.5, 0.1, 0))
	victim.call("take_damage", 9999.0)
	await _frames(2)
	var eater := _spawn(Vector3(-1.0, 0.1, 0), target)
	eater.get("_senses").wander_enabled = false
	await _frames(3)
	_check(eater.call("_find_corpse") == victim, "A hunter finds the corpse next to it.")
	eater.set("_corpse", victim)
	eater.get("_senses").hear(eater, victim.global_position, 9.0)
	eater.get("_senses").state = 2 # SEARCH: it has reached the body
	eater.call("_rest_behaviour", 0.016)
	_check(bool(eater.call("is_feeding")), "Next to a corpse the hunter starts to feed.")
	_check(_player_of(eater).current_animation == "BiteDown", "It goes down with the first half of the biting clip.")
	# BiteDown hands over to BiteLoop after its own length; wait for it by frames
	# (bounded) so a slow runner does not turn the clip length into a race.
	var waited := 0
	while _player_of(eater).current_animation != "BiteLoop" and waited < 600:
		await physics_frame
		waited += 1
	_check(_player_of(eater).current_animation == "BiteLoop", "Then it gnaws on all fours (%s)." % _player_of(eater).current_animation)
	# Keep the target in charge range relative to the current eater position.
	# A feral fixture stays on all fours when the chase phase re-evaluates it.
	target.position = eater.global_position + Vector3(0, 0, -8)
	eater.set("_feral", true)
	eater.call("hear_alert", eater.global_position, 50.0)
	# The meal ends on the frame the chase starts; read the posture on that frame,
	# since the chase pace may stand it up again a tick later.
	var frames_waited := 0
	while bool(eater.call("is_feeding")) and frames_waited < 30:
		await physics_frame
		frames_waited += 1
	_check(not bool(eater.call("is_feeding")), "A cry from a neighbour interrupts the meal.")
	_check(eater.get("posture") == 1, "It leaps up on all fours.")
	eater.queue_free()
	victim.queue_free()
	await process_frame


# A planner-baked corpse is a decor node, not a killed infected: it still lies
# on the floor and must be found and gnawed.
func _baked_corpse_feeding() -> void:
	await _fresh_stage()
	var target := Target.new()
	stage.add_child(target)
	target.position = Vector3(0, 0.1, -40)
	var baked := BAKED_CORPSE.instantiate() as Node3D
	stage.add_child(baked)
	baked.global_position = Vector3(1.5, 0.1, 0)
	await _frames(2)
	var eater := _spawn(Vector3(-1.0, 0.1, 0), target)
	eater.get("_senses").wander_enabled = false
	await _frames(3)
	_check(eater.call("_find_corpse") == baked, "A hunter finds a baked corpse next to it.")
	eater.set("_corpse", baked)
	eater.get("_senses").hear(eater, baked.global_position, 9.0)
	eater.get("_senses").state = 2 # SEARCH: it has reached the body
	eater.call("_rest_behaviour", 0.016)
	_check(bool(eater.call("is_feeding")), "Next to a baked corpse the hunter gnaws it.")
	eater.queue_free()
	baked.queue_free()
	await process_frame


func _flinch() -> void:
	await _fresh_stage()
	var target := Target.new()
	stage.add_child(target)
	target.position = Vector3(0, 0.1, -3)
	var enemy := _spawn(Vector3(0, 0.1, 0))
	enemy.call("set_target", target)
	await _frames(3)
	await create_timer(0.1).timeout
	enemy.call("take_projectile_damage", 16.0, Vector3(0, 1.4, -0.4), Vector3(0, 0, 1), "PISTOL")
	var driver := enemy.get_node("AnimationDriver")
	_check(driver.hit_reaction != null and driver.hit_reaction.get("_velocity").length() > 0.0, "A directional bullet hit drives the torso spring while legs keep moving.")
	enemy.queue_free()
	await process_frame


func _postures() -> void:
	await _fresh_stage()
	var target := Target.new()
	stage.add_child(target)
	target.position = Vector3(0, 0.1, -20)
	var enemy := _spawn(Vector3(0, 0.1, 0))
	enemy.call("set_target", target)
	await _frames(2)
	enemy.set("_feral", true)
	enemy.set("_distance", 12.0)
	enemy.get("_pace").charging = true
	enemy.call("_update_posture")
	_check(enemy.get("posture") == 1, "A feral hunter charging from afar drops to all fours.")
	enemy.set("_distance", 3.0)
	enemy.call("_update_posture")
	_check(enemy.get("posture") == 0, "It stands up as it closes in.")
	enemy.set("posture", 1)
	enemy.call("_try_attack")
	_check(enemy.get("posture") == 0 and bool(enemy.call("is_busy")), "On all fours it has to stand up before it can swing.")
	_check(_player_of(enemy).current_animation == "RiseFromFours", "It stands up with the rise clip.")
	enemy.queue_free()
	await process_frame


func _crawl_attack() -> void:
	await _fresh_stage()
	var target := Target.new()
	stage.add_child(target)
	target.position = Vector3(0, 0.1, -1.0)
	var enemy := _spawn(Vector3(0, 0.1, 0))
	enemy.call("set_target", target)
	enemy.get("_parts").sever(&"leg_l", Vector3.LEFT)
	await create_timer(1.6).timeout
	var player := _player_of(enemy)
	_check(enemy.get("posture") == 2, "The one-legged hunter is crawling.")
	await create_timer(1.5).timeout
	_check(target.damage > 0.0, "A crawling hunter still hurts (%.0f damage)." % target.damage)
	enemy.queue_free()
	await process_frame
