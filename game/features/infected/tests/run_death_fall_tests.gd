extends SceneTree
## Directional enemy deaths (ADR-0034): a moving infected shot from afar falls
## forward, a close shotgun blast throws it back, a grenade throws it away
## from the explosion, and walls stop a thrown body.

const FALL := preload("res://game/features/infected/death_fall.gd")
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
	_add_box(stage, Vector3(0, -0.5, 0), Vector3(200, 1, 200), 2)
	await _test_charging_falls_forward(stage)
	await _test_close_shotgun_throws_back(stage)
	await _test_grenade_throws_away(stage)
	await _test_wall_stops_body(stage)
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


func _test_charging_falls_forward(stage: Node3D) -> void:
	var enemy := await _spawn(stage, Vector3(0, 1, 0))
	var start := enemy.global_position
	enemy.velocity = Vector3(0, 0, -5.4)
	enemy.call("take_projectile_damage", 1000.0, start, Vector3(0, 0, 1), "PISTOL")
	_expect(_clip(enemy) == "DeathForward", "A charging infected shot by a pistol plays the forward fall (%s)." % _clip(enemy))
	await create_timer(0.7).timeout
	_expect(enemy.global_position.z < start.z - 0.4, "Its momentum carries the body forward.")
	enemy.queue_free()
	await process_frame


func _test_close_shotgun_throws_back(stage: Node3D) -> void:
	var enemy := await _spawn(stage, Vector3(10, 1, 0))
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = Vector3(10, 1, -1.5)
	enemy.call("set_target", target)
	var start := enemy.global_position
	enemy.call("take_projectile_damage", 1000.0, start, Vector3(0, 0, 1), "SHOTGUN")
	_expect(_clip(enemy) == "DeathBack", "A close shotgun kill plays the thrown-back fall (%s)." % _clip(enemy))
	await create_timer(0.7).timeout
	_expect(enemy.global_position.z > start.z + 1.0, "The shotgun throws the body back from the shooter.")
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_grenade_throws_away(stage: Node3D) -> void:
	var enemy := await _spawn(stage, Vector3(20, 1, 0))
	var start := enemy.global_position
	var yaw := enemy.rotation.y
	enemy.call("take_blast_damage", 140.0, start + Vector3(-1.5, -0.8, 0))
	await create_timer(0.7).timeout
	var travel := enemy.global_position - start
	_expect(travel.x > 0.8 and absf(travel.z) < 0.2, "The grenade throws the body away from the explosion (%s)." % travel)
	_expect(absf(angle_difference(yaw, enemy.rotation.y)) > 1.2, "The body turns into its sideways fall.")
	enemy.queue_free()
	await process_frame


func _test_wall_stops_body(stage: Node3D) -> void:
	var wall := _add_box(stage, Vector3(30, 1, 1.0), Vector3(4, 2, 0.2), 1)
	var enemy := await _spawn(stage, Vector3(30, 1, 0))
	var start := enemy.global_position
	enemy.call("take_blast_damage", 155.0, start + Vector3(0, -0.8, -0.5))
	await create_timer(0.7).timeout
	_expect(enemy.global_position.z < 0.75, "A wall stops the thrown body (%.2f)." % enemy.global_position.z)
	enemy.queue_free()
	wall.queue_free()
	await process_frame


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
