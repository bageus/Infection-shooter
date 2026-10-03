extends SceneTree
## Runtime checks for destructible bodies (ADR-0017): part picking, wounds,
## severing and its consequences, falling bleeding pieces, shootable corpses,
## size-scaled durability, the larger Horde and corpse/part decorations.

const ZOMBIE := preload("res://game/features/infected/public/infected_capsule.tscn")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const TITAN := preload("res://game/features/infected/public/infected_titan.tscn")
const COLOSSUS := preload("res://game/features/infected/public/infected_colossus.tscn")
const HORDE := preload("res://game/features/infected/public/infected_horde.tscn")
const CORPSE := "res://game/features/infected/public/decor/corpse_hunger_mutilated.tscn"
const PART := "res://game/features/infected/public/decor/part_titan_arm.tscn"

class FakeTarget:
	extends Node3D
	var damage_taken := 0.0
	func take_damage(amount: float, _kind: String = "physical") -> void:
		damage_taken += amount

var failures := 0
var _events: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	_add_floor(stage)
	await _test_arm_shot_off(stage)
	await _test_headshot_kills(stage)
	await _test_small_enemy_dies_from_leg(stage)
	await _test_large_enemy_limps_and_fights_one_armed(stage)
	await _test_durability_scales_with_size(stage)
	await _test_corpse_stays_shootable(stage)
	await _test_blast_tears_limbs(stage)
	await _test_horde_size_and_tentacles(stage)
	await _test_decorations(stage)
	stage.queue_free()
	await process_frame
	print("Dismemberment tests: %d failure(s)." % failures)
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


func _spawn(stage: Node3D, scene: PackedScene, at: Vector3) -> CharacterBody3D:
	var enemy := scene.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = at
	await process_frame
	enemy.set_physics_process(false)
	return enemy


# Fires shots from the enemy's side through the middle of a part.
func _shoot(enemy: Node, part: StringName, damage: float, shots: int, weapon := "PISTOL") -> void:
	var parts: Node = enemy.get("_parts")
	for i in shots:
		if bool(enemy.get("_dead")) or parts.is_severed(part):
			return
		var segments: Array = parts.parts[part].segments
		var segment: Dictionary = segments[mini(1, segments.size() - 1)]
		var target: Vector3 = parts._world(segment.bone, (segment.start + segment.end) * 0.5)
		var outward := target - (enemy as Node3D).global_position
		outward.y = 0.0
		var direction := -outward.normalized() if outward.length() > 0.12 else Vector3(0.0, 0.0, 1.0)
		enemy.call("take_projectile_damage", damage, target - direction * 0.35, direction, weapon)
		await process_frame


func _pieces(stage: Node3D) -> Array[Node]:
	var result: Array[Node] = []
	for child in stage.get_children():
		if child is RigidBody3D and child.has_method("start_bleeding"):
			result.append(child)
	return result


func _test_arm_shot_off(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER, Vector3(0, 1.0, 0))
	var parts: Node = enemy.get("_parts")
	_expect(parts != null, "Hunger has destructible body parts.")
	if parts == null:
		return
	enemy.connect("limb_severed", func(_p: Vector3, _d: Vector3, _e: Array[RID]) -> void: _events.append("severed"))
	var segment: Dictionary = parts.parts[&"arm_l"].segments[1]
	var through: Vector3 = parts._world(segment.bone, (segment.start + segment.end) * 0.5)
	var inward := Vector3(enemy.global_position.x - through.x, 0.0, enemy.global_position.z - through.z).normalized()
	_expect(parts.pick_part(through - inward * 0.35, inward) == &"arm_l", "A shot through the left forearm picks the left arm.")
	_expect(parts.pick_part(enemy.global_position + Vector3(0, 0.2, -0.6), Vector3(0, 0, 1)) == &"torso", "A shot through the belly picks the torso.")
	var before := _pieces(stage).size()
	await _shoot(enemy, &"arm_l", 12.0, 1)
	var wounds: PackedVector4Array = (parts._entries[0].materials[0] as ShaderMaterial).get_shader_parameter("wounds")
	var painted := false
	for w in wounds:
		if w.w > 0.0:
			painted = true
	_expect(painted, "A hit paints a wound on the skin.")
	await _shoot(enemy, &"arm_l", 12.0, 6)
	_expect(parts.is_severed(&"arm_l"), "Enough damage shoots the arm off.")
	_expect(not bool(enemy.get("_dead")), "Losing an arm does not kill.")
	_expect(_events.has("severed"), "Severing emits a limb_severed blood fact.")
	var pieces := _pieces(stage)
	_expect(pieces.size() == before + 1, "The arm drops as a separate physics piece.")
	_expect(enemy.call("_attack_state") == &"attack_right", "A one-armed enemy attacks with the remaining arm.")
	if pieces.size() > before:
		var piece := pieces[pieces.size() - 1] as RigidBody3D
		var bled := [false]
		piece.connect("blood_wounded", func(_p: Vector3, _e: Array[RID]) -> void: bled[0] = true)
		await create_timer(1.6).timeout
		_expect(piece.global_position.y < 0.5, "The severed arm falls to the floor (y=%.2f)." % piece.global_position.y)
		_expect(bled[0], "The fallen arm leaves blood where it lands.")
		_expect(piece.collision_layer == 4, "Severed parts stay shootable but never block characters.")
		piece.queue_free()
	enemy.queue_free()
	await process_frame


func _test_headshot_kills(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER, Vector3(4, 1.0, 0))
	await _shoot(enemy, &"head", 30.0, 3)
	_expect(enemy.get("_parts").is_severed(&"head"), "Headshots take the head off.")
	_expect(bool(enemy.get("_dead")), "A headless enemy dies.")
	enemy.queue_free()
	await process_frame


func _test_small_enemy_dies_from_leg(stage: Node3D) -> void:
	var enemy := await _spawn(stage, ZOMBIE, Vector3(8, 1.0, 0))
	await _shoot(enemy, &"leg_r", 12.0, 6)
	_expect(enemy.get("_parts").is_severed(&"leg_r"), "The zombie's leg can be shot off.")
	_expect(bool(enemy.get("_dead")), "A small infected dies from losing a leg.")
	enemy.queue_free()
	await process_frame


func _test_large_enemy_limps_and_fights_one_armed(stage: Node3D) -> void:
	var enemy := await _spawn(stage, TITAN, Vector3(12, 1.5, 0))
	enemy.set("max_health", 100000.0)
	enemy.set("health", 100000.0)
	var parts: Node = enemy.get("_parts")
	await _shoot(enemy, &"leg_l", 60.0, 12)
	_expect(parts.is_severed(&"leg_l"), "The Titan's leg can be shot off.")
	_expect(not bool(enemy.get("_dead")), "A large infected survives losing a leg.")
	_expect(float(enemy.get("_mobility")) < 0.6, "It limps on at reduced speed.")
	await _shoot(enemy, &"arm_r", 60.0, 12)
	_expect(parts.is_severed(&"arm_r") and not bool(enemy.get("_dead")), "It keeps fighting after losing an arm.")
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, -1.2)
	enemy.set_physics_process(true)
	enemy.call("set_target", target)
	var player := enemy.get_node("AnimationDriver").get("animation_player") as AnimationPlayer
	await physics_frame
	await physics_frame
	_expect(player.current_animation == "AttackLeft", "The one-armed Titan swings its left arm.")
	await create_timer(player.get_animation("AttackLeft").length * 0.5 + 0.1).timeout
	_expect(target.damage_taken > 0.0, "Its one-armed blow still lands.")
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_durability_scales_with_size(stage: Node3D) -> void:
	var small := await _spawn(stage, HUNGER, Vector3(16, 1.0, 0))
	var large := await _spawn(stage, COLOSSUS, Vector3(20, 1.5, 0))
	var small_arm := float(small.get("_parts").parts[&"arm_l"].max_hp)
	var large_arm := float(large.get("_parts").parts[&"arm_l"].max_hp)
	_expect(large_arm > small_arm * 8.0, "A Colossus arm takes far more damage than a Hunger arm (%.0f vs %.0f)." % [large_arm, small_arm])
	small.queue_free()
	large.queue_free()
	await process_frame


func _test_corpse_stays_shootable(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER, Vector3(24, 1.0, 0))
	enemy.set("death_linger_seconds", 10.0)
	enemy.call("_apply_damage", 500.0, false) # a plain kill, not a limb-tearing blast
	await create_timer(1.6).timeout
	var parts: Node = enemy.get("_parts")
	var hitboxes := enemy.find_children("*", "StaticBody3D", true, false).filter(func(n: Node) -> bool: return n.has_method("take_projectile_hit"))
	_expect(not hitboxes.is_empty(), "A corpse gets bullet hit volumes on its parts.")
	var leg_box: Node = null
	for box in hitboxes:
		if box.get("part") == &"leg_l":
			leg_box = box
	var dropped: Array = []
	parts.part_severed.connect(func(_part: StringName, piece: RigidBody3D) -> void: dropped.append(piece))
	if leg_box != null:
		for i in 6:
			leg_box.call("take_projectile_hit", 15.0, (leg_box as Node3D).global_position, Vector3.UP, Vector3(1, 0, 0), "PISTOL")
	_expect(parts.is_severed(&"leg_l"), "Shooting the corpse's leg takes it off.")
	_expect(dropped.size() == 1 and dropped[0] != null, "The corpse's leg drops as a piece (%s)." % [dropped])
	enemy.queue_free()
	await process_frame
	for piece in _pieces(stage):
		piece.queue_free()


func _test_blast_tears_limbs(stage: Node3D) -> void:
	var enemy := await _spawn(stage, TITAN, Vector3(28, 1.5, 0))
	enemy.set("max_health", 100000.0)
	enemy.set("health", 100000.0)
	var parts: Node = enemy.get("_parts")
	enemy.call("take_damage", 200.0)
	var damaged := 0
	for part: StringName in parts.parts:
		if float(parts.part_ratio(part)) < 1.0:
			damaged += 1
	_expect(damaged >= 1, "A heavy blast tears at the limbs (%d damaged)." % damaged)
	enemy.queue_free()
	await process_frame


func _test_horde_size_and_tentacles(stage: Node3D) -> void:
	var horde := await _spawn(stage, HORDE, Vector3(-10, 1.2, 10))
	var titan := await _spawn(stage, TITAN, Vector3(-14, 1.5, 10))
	var horde_radius := ((horde.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D).radius
	var titan_radius := ((titan.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D).radius
	_expect(horde_radius > titan_radius * 1.3, "The Horde is the bulkiest infected.")
	var parts: Node = horde.get("_parts")
	_expect(parts != null and int(parts.remaining("tentacle")) == 8, "The Horde has eight tentacle legs.")
	if parts != null:
		parts.sever(&"tentacle_2", Vector3.RIGHT)
		parts.sever(&"tentacle_3", Vector3.RIGHT)
		horde.call("_part_lost", &"tentacle_3")
		_expect(float(horde.get("_mobility")) < 1.0, "Lost tentacles slow the Horde.")
		_expect(not bool(horde.get("_dead")), "Losing tentacles does not kill the Horde.")
	horde.queue_free()
	titan.queue_free()
	await process_frame
	for piece in _pieces(stage):
		piece.queue_free()


func _test_decorations(stage: Node3D) -> void:
	var corpse := (load(CORPSE) as PackedScene).instantiate() as Node3D
	stage.add_child(corpse)
	await process_frame
	var parts: Node = corpse.get("parts")
	_expect(parts != null and parts.is_severed(&"head") and parts.is_severed(&"arm_r"), "The mutilated corpse decoration starts without head and arm.")
	_expect(not corpse.find_children("*", "StaticBody3D", true, false).is_empty(), "Corpse decorations can be shot.")
	var piece := (load(PART) as PackedScene).instantiate() as RigidBody3D
	stage.add_child(piece)
	piece.global_position = Vector3(-20, 1.0, -10)
	await create_timer(1.2).timeout
	var meshes := piece.find_children("*", "MeshInstance3D", true, false)
	_expect(meshes.size() >= 1 and (meshes[0] as MeshInstance3D).mesh.get_surface_count() >= 1, "The arm decoration has the Titan's arm mesh.")
	_expect(piece.global_position.y < 0.6, "The arm decoration rests on the floor.")
	_expect(not piece.is_in_group("infected_severed_part"), "Decorations never expire with combat debris.")
	corpse.queue_free()
	piece.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
