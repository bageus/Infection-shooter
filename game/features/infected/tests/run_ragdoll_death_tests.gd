extends SceneTree
## Ragdoll deaths (ADR-0041): a killed infected is not animated; it falls with
## the momentum it had and the push of the killing blow, stops against walls,
## lies across tables, and the ragdoll never stretches or flies off.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const GUARD := preload("res://game/features/infected/corpse_guard.gd")
const CORPSE := preload("res://game/features/infected/public/decor/corpse_hunger.tscn")

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
	_add_box(Vector3(0, -0.5, 0), Vector3(400, 1, 400))
	await _test_charging_falls_forward()
	await _test_close_shotgun_throws_back()
	await _test_grenade_throws_away()
	await _test_standing_collapses()
	await _test_wall_stops_body()
	await _test_body_rests_on_table()
	await _test_corpse_sinks_and_hides()
	await _test_planner_corpse_survives_overlap()
	await _test_stretched_ragdoll_is_recovered()
	print("Ragdoll death tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _test_charging_falls_forward() -> void:
	var enemy := await _spawn(Vector3(0, 1, 0))
	var start := enemy.global_position
	enemy.velocity = Vector3(0, 0, -5.4)
	enemy.call("take_projectile_damage", 1000.0, start, Vector3(0, 0, 1), "PISTOL")
	_expect(enemy.get("_ragdoll") != null, "A kill starts a ragdoll.")
	_expect(_clip(enemy) != "DeathForward" and _clip(enemy) != "Death", "No death clip plays (%s)." % _clip(enemy))
	await create_timer(2.0).timeout
	_expect(_bone(enemy, "Head").z < start.z - 0.5, "Running momentum carries the head forward (%s)." % _bone(enemy, "Head"))
	_expect(_bone(enemy, "Head").y < 0.5, "The body lies on the floor (head %.2f m)." % _bone(enemy, "Head").y)
	_expect(_stretch(enemy) < 0.2, "The ragdoll joints keep their length (%.2f)." % _stretch(enemy))
	enemy.queue_free()
	await process_frame


func _test_close_shotgun_throws_back() -> void:
	var enemy := await _spawn(Vector3(10, 1, 0))
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = Vector3(10, 1, -1.5)
	enemy.call("set_target", target)
	var start := enemy.global_position
	enemy.call("take_projectile_damage", 1000.0, start, Vector3(0, 0, 1), "SHOTGUN")
	await create_timer(2.0).timeout
	_expect(_bone(enemy, "Hips").z > start.z + 0.8, "The shotgun throws the body back from the shooter (%s)." % _bone(enemy, "Hips"))
	_expect(_stretch(enemy) < 0.2, "The thrown ragdoll keeps its joints (%.2f)." % _stretch(enemy))
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_grenade_throws_away() -> void:
	var enemy := await _spawn(Vector3(20, 1, 0))
	var start := enemy.global_position
	enemy.call("take_blast_damage", 140.0, start + Vector3(-1.5, -0.8, 0))
	await create_timer(2.0).timeout
	var travel := _bone(enemy, "Hips") - start
	_expect(travel.x > 0.8 and absf(travel.z) < 1.0, "The grenade throws the body away from the explosion (%s)." % travel)
	enemy.queue_free()
	await process_frame


func _test_standing_collapses() -> void:
	var enemy := await _spawn(Vector3(25, 1, 0))
	var start := enemy.global_position
	enemy.call("take_projectile_damage", 1000.0, start, Vector3(0, 0, 1), "PISTOL")
	await create_timer(2.0).timeout
	_expect(_bone(enemy, "Head").y < 0.8, "A standing infected collapses to the floor (head %.2f m)." % _bone(enemy, "Head").y)
	_expect(Vector2(_bone(enemy, "Hips").x - start.x, _bone(enemy, "Hips").z - start.z).length() < 1.5, "It stays where it stood.")
	enemy.queue_free()
	await process_frame


func _test_wall_stops_body() -> void:
	var wall := _add_box(Vector3(30, 1, 1.0), Vector3(4, 2, 0.2))
	var enemy := await _spawn(Vector3(30, 1, 0))
	var start := enemy.global_position
	enemy.call("take_blast_damage", 155.0, start + Vector3(0, -0.8, -0.5))
	await create_timer(2.0).timeout
	# A blast may tear limbs off, so every remaining volume is checked.
	for bone: PhysicalBone3D in enemy.find_children("Physics_*", "PhysicalBone3D", true, false):
		_expect(bone.global_position.z < 1.0, "A wall stops the thrown %s (%.2f)." % [bone.name, bone.global_position.z])
	enemy.queue_free()
	wall.queue_free()
	await process_frame


# A charging infected killed beside a table falls onto it and stays on the top.
func _test_body_rests_on_table() -> void:
	var table := _add_box(Vector3(40, 0.375, -1.0), Vector3(3, 0.75, 0.8))
	var enemy := await _spawn(Vector3(40, 1, 0))
	enemy.velocity = Vector3(0, 0, -5.4)
	enemy.call("take_projectile_damage", 1000.0, enemy.global_position, Vector3(0, 0, 1), "PISTOL")
	await create_timer(2.5).timeout
	var chest := _bone(enemy, "Head")
	_expect(chest.y > 0.6 or _bone(enemy, "Hips").y > 0.6, "The body is caught by the table, not under it (head %.2f, hips %.2f)." % [chest.y, _bone(enemy, "Hips").y])
	enemy.queue_free()
	table.queue_free()
	await process_frame


func _test_corpse_sinks_and_hides() -> void:
	var enemy := await _spawn(Vector3(50, 1, 0))
	enemy.set("death_linger_seconds", 0.3)
	enemy.call("take_projectile_damage", 1000.0, enemy.global_position, Vector3(0, 0, 1), "PISTOL")
	await create_timer(3.0).timeout
	_expect(not (enemy.get("body_visual") as Node3D).visible, "The body is hidden after it sank.")
	enemy.queue_free()
	await process_frame


# Two bodies placed inside each other must not launch or stretch.
func _test_planner_corpse_survives_overlap() -> void:
	var first := _place_corpse(Vector3(60, 0.3, 0))
	var second := _place_corpse(Vector3(60, 0.3, 0.05))
	await create_timer(0.5).timeout
	first.call("set_runtime_physics", true)
	second.call("set_runtime_physics", true)
	await create_timer(3.0).timeout
	for corpse in [first, second]:
		var hips := _bone(corpse, "Hips")
		_expect(Vector2(hips.x - 60.0, hips.z).length() < 4.0 and hips.y < 3.0, "Overlapping corpses stay put (%s)." % hips)
		_expect(_stretch(corpse) < 0.2, "Overlapping corpses are not stretched (%.2f)." % _stretch(corpse))
		corpse.queue_free()
	await process_frame


# A joint pulled apart by hand snaps back to its last healthy pose.
func _test_stretched_ragdoll_is_recovered() -> void:
	var corpse := _place_corpse(Vector3(70, 0.3, 0))
	corpse.call("set_runtime_physics", true)
	await create_timer(1.0).timeout
	var guard: Node = corpse.get("parts").get("skeleton").get_node("CorpseGuard")
	var bones: Array = guard.get("bones")
	bones[bones.size() - 1].global_position += Vector3(0, 4, 0)
	await create_timer(0.6).timeout
	_expect(_stretch(corpse) < 0.2, "A stretched ragdoll is recovered (%.2f)." % _stretch(corpse))
	corpse.queue_free()
	await process_frame


func _place_corpse(at: Vector3) -> Node3D:
	var corpse := CORPSE.instantiate() as Node3D
	corpse.call("configure_decor_pose", {"seed": 9, "pose": "back", "facing": 0.0})
	stage.add_child(corpse)
	corpse.global_position = at
	return corpse


# Largest deviation of a ragdoll joint from its anatomical length.
func _stretch(owner: Node) -> float:
	var skeleton := owner.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var guard := skeleton.get_node("CorpseGuard")
	var worst := 0.0
	for link: Dictionary in guard.get("_links"):
		var joint_a := _joint(link["child"])
		var joint_b := _joint(link["parent"])
		worst = maxf(worst, absf(joint_a.distance_to(joint_b) - float(link["length"])))
	return worst


func _joint(bone: PhysicalBone3D) -> Vector3:
	return bone.global_transform * bone.body_offset.affine_inverse().origin


# Centre of the physical volume of a bone: what the skin follows.
func _bone(owner: Node, bone_name: String) -> Vector3:
	var volume := owner.find_child("Physics_" + bone_name, true, false) as PhysicalBone3D
	if volume == null: # The part was shot off; the torso stays.
		volume = owner.find_child("Physics_Hips", true, false) as PhysicalBone3D
	return volume.global_position


func _spawn(at: Vector3) -> CharacterBody3D:
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = at
	await process_frame
	await process_frame
	return enemy


func _clip(enemy: Node) -> String:
	var player := enemy.get_node("AnimationDriver").get("animation_player") as AnimationPlayer
	return str(player.current_animation) if player != null else ""


func _add_box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
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
