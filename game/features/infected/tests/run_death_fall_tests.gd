extends SceneTree
## Directional enemy deaths (ADR-0034): the rules that pick the fall direction,
## the baked fall clips and the clip fallback used when too many ragdolls run
## (ADR-0041). Ragdoll deaths are covered by run_ragdoll_death_tests.gd.

const FALL := preload("res://game/features/infected/death_fall.gd")
const RAGDOLL := preload("res://game/features/infected/death_ragdoll.gd")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const HUMANOID_RIGS := ["Hunger", "Revenant", "Brute", "Titan", "Colossus"]

class FakeTarget:
	extends Node3D
	func take_damage(_amount: float, _kind: String = "physical") -> void:
		pass

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_rules()
	_test_clips()
	var stage := Node3D.new()
	root.add_child(stage)
	_add_box(stage, Vector3(0, -0.5, 0), Vector3(200, 1, 200), 3)
	await _test_clip_fallback(stage)
	await _test_part_falls(stage)
	await _test_legs_settle(stage)
	print("Death fall tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _test_rules() -> void:
	var forward := Vector3(0, 0, -1)
	var shot := Vector3(0, 0, 1)
	var walking := FALL.resolve(forward * 2.16, FALL.hit_push("PISTOL", shot, 15.0), forward, 1.0)
	_expect(walking["state"] == FALL.DEATH_FORWARD, "A walking infected shot by a pistol falls forward.")
	var running := FALL.resolve(forward * 5.4, FALL.hit_push("RIFLE", shot, 12.0), forward, 1.0)
	_expect(running["state"] == FALL.DEATH_FORWARD and absf(running["turn"]) < 0.01, "A charging infected shot from afar falls straight forward.")
	var colossus := FALL.resolve(forward * 1.16, FALL.hit_push("UZI", shot, 10.0), forward, 1.55)
	_expect(colossus["state"] == FALL.DEATH_FORWARD, "A walking Colossus also falls forward.")
	var close := FALL.resolve(forward * 5.4, FALL.hit_push("SHOTGUN", shot, 2.0), forward, 1.0)
	_expect(close["state"] == FALL.DEATH_BACK, "A close shotgun blast throws a charging infected back.")
	_expect((close["slide"] as Vector3).dot(shot) > 0.8, "The thrown body travels away from the shooter.")
	var far := FALL.resolve(forward * 5.4, FALL.hit_push("SHOTGUN", shot, 12.0), forward, 1.0)
	_expect(far["state"] == FALL.DEATH_FORWARD, "Spent shotgun pellets from afar do not stop a charge.")
	var standing := FALL.resolve(Vector3.ZERO, FALL.hit_push("PISTOL", shot, 6.0), forward, 1.0)
	_expect(standing["state"] == FALL.DEATH, "A standing infected shot by a pistol collapses backward.")
	var blast := FALL.resolve(Vector3.ZERO, FALL.blast_push(Vector3(-2, 0, 0), Vector3.ZERO, 0.6), forward, 1.0)
	var away := Vector3(1, 0, 0)
	_expect((blast["slide"] as Vector3).normalized().dot(away) > 0.99, "A blast throws the body away from the explosion.")
	var clip_fall := forward if blast["state"] == FALL.DEATH_FORWARD else -forward
	_expect(clip_fall.rotated(Vector3.UP, blast["turn"]).dot(away) > 0.99, "The body turns so its fall points away from the blast.")
	var still := FALL.resolve(Vector3.ZERO, Vector3.ZERO, forward, 1.0)
	_expect(still["state"] == FALL.DEATH and (still["slide"] as Vector3).is_zero_approx(), "Without a blow the body collapses where it stands.")


# Model +Z is the front: forward falls end with the head ahead of the feet.
func _test_clips() -> void:
	for enemy: String in HUMANOID_RIGS:
		var rig := (load("res://models/objects/characters/enemy/game/%s_rig.tscn" % enemy) as PackedScene).instantiate() as Node3D
		root.add_child(rig)
		var player := rig.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var height := skeleton.get_bone_global_rest(skeleton.find_bone("Head")).origin.y - skeleton.get_bone_global_rest(skeleton.find_bone("L_Foot")).origin.y
		for clip in ["DeathForward", "DeathBack"]:
			_expect(player.has_animation(clip), "%s has %s." % [enemy, clip])
			if not player.has_animation(clip):
				continue
			player.play(clip)
			player.seek(player.get_animation(clip).length, true)
			player.advance(0.0)
			var head := skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
			var foot := skeleton.get_bone_global_pose(skeleton.find_bone("L_Foot")).origin
			_expect(absf(head.y - foot.y) < 0.3 * height, "%s %s ends lying on the floor." % [enemy, clip])
			var ahead := head.z - foot.z
			_expect(ahead > 0.5 * height if clip == "DeathForward" else ahead < -0.5 * height, "%s %s falls the right way." % [enemy, clip])
		rig.queue_free()


# With every ragdoll slot busy a death still plays its directional clip.
func _test_clip_fallback(stage: Node3D) -> void:
	RAGDOLL._active = RAGDOLL.MAX_ACTIVE
	var enemy := await _spawn(stage, Vector3(0, 1, 0))
	var start := enemy.global_position
	enemy.velocity = Vector3(0, 0, -5.4)
	enemy.call("take_projectile_damage", 1000.0, start, Vector3(0, 0, 1), "PISTOL")
	_expect(_clip(enemy).begins_with("DeathForward"), "Without a free ragdoll slot the forward fall clip plays (%s)." % _clip(enemy))
	await create_timer(0.7).timeout
	_expect(enemy.global_position.z < start.z - 0.4, "The clip fall still carries the body forward.")
	RAGDOLL._active = 0
	enemy.queue_free()
	await process_frame


# A killing head shot throws the head back even on the run; without a leg the body drops to its side.
func _test_part_falls(stage: Node3D) -> void:
	RAGDOLL._active = RAGDOLL.MAX_ACTIVE
	for case: Array in [["Head", "DeathBack"], ["R_Shin", "DeathSide"], ["L_Shin", "DeathSide2"]]:
		var enemy := await _spawn(stage, Vector3(0, 1, 0))
		enemy.velocity = Vector3(0, 0, -5.4)
		var at := _bone(enemy, case[0])
		# Limbs come off by chance now: wound the spot until it is gone, then land the killing shot.
		var part: StringName = enemy.get("_parts").pick_part(at, Vector3(0, 0, 1))
		for _i in 60:
			if enemy.get("_parts").is_severed(part):
				break
			enemy.call("take_projectile_damage", 1.0, at, Vector3(0, 0, 1), "AK")
		enemy.call("take_projectile_damage", 1000.0, at, Vector3(0, 0, 1), "AK")
		_expect(_clip(enemy) == case[1] or _clip(enemy) == "DeathCrawl" or (case[0] == "Head" and _clip(enemy).begins_with("DeathBack")), "A killing shot at %s plays %s (%s)." % [case[0], case[1], _clip(enemy)])
		enemy.queue_free()
		await process_frame
	# A crawler is already down: it settles flat on its belly with the DeathCrawl clip and does not hang.
	var crawler := await _spawn(stage, Vector3(0, 1, 0))
	crawler.set("posture", 2) # Posture.CRAWL
	crawler.call("take_projectile_damage", 1000.0, _bone(crawler, "Head"), Vector3(0, 0, 1), "PISTOL")
	_expect(_clip(crawler) == "DeathCrawl", "A crawler dies with DeathCrawl (%s)." % _clip(crawler))
	_expect(crawler.get("_fall_watch") == null, "A crawler's death has no obstacle watcher.")
	var player := crawler.get_node("AnimationDriver").get("animation_player") as AnimationPlayer
	await create_timer(1.0).timeout
	_expect(not player.is_playing() or player.current_animation_position >= player.current_animation_length - 0.05, "The crawler's clip ran to its end.")
	crawler.queue_free()
	# Each fall has several finished poses (mirrored, limbs spread): all of them end lying on the floor.
	var lengths := {}
	for enemy_name in ["Hunger", "Titan"]:
		var rig := load("res://models/objects/characters/enemy/game/%s_mixamo.res" % enemy_name) as AnimationLibrary
		for pose: String in ["DeathForward", "DeathBack", "DeathSide"]:
			for number in ["", "2", "3", "4"]:
				_expect(rig.has_animation(pose + number), "%s has %s." % [enemy_name, pose + number])
	await process_frame
	RAGDOLL._active = 0


# A death clip may end with a leg in the air: the legs come down onto the floor afterwards.
func _test_legs_settle(stage: Node3D) -> void:
	RAGDOLL._active = RAGDOLL.MAX_ACTIVE
	for weapon in ["SHOTGUN", "PISTOL"]:
		var enemy := await _spawn(stage, Vector3(0, 0.96, 0))
		enemy.velocity = Vector3(0, 0, 0)
		enemy.call("take_projectile_damage", 1000.0, enemy.global_position, Vector3(0, 0, -1), weapon)
		await create_timer(4.0).timeout
		var feet := maxf(_bone(enemy, "L_Foot").y, _bone(enemy, "R_Foot").y)
		_expect(feet < 0.3, "After a %s death both feet lie on the floor (highest %.2f m)." % [weapon, feet])
		enemy.queue_free()
		await process_frame
	RAGDOLL._active = 0


func _bone(enemy: Node, bone_name: String) -> Vector3:
	var skeleton := enemy.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin


func _spawn(stage: Node3D, at: Vector3) -> CharacterBody3D:
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = at
	await process_frame
	await process_frame
	return enemy


func _clip(enemy: Node) -> String:
	var player := enemy.get_node("AnimationDriver").get("animation_player") as AnimationPlayer
	return str(player.current_animation) if player != null else ""


func _add_box(stage: Node3D, at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	stage.add_child(body)
	body.position = at
	return body


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
