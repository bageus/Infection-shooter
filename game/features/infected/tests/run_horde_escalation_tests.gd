extends SceneTree

const HORDE := preload("res://game/features/infected/public/infected_horde.tscn")
const RULE := preload("res://game/features/infected/domain/horde_summon.gd")
const LEGACY := preload("res://game/features/infected/public/mutant_level2.tscn")
var failures := 0


class Target:
	extends Node3D
	func take_damage(_amount: float, _kind := "physical") -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(RULE.tier(150, 150) == RULE.Tier.HUNGER, "Full health calls Hunger")
	_check(RULE.tier(100.01, 150) == RULE.Tier.HUNGER, "Above two thirds remains Hunger")
	_check(RULE.tier(100, 150) == RULE.Tier.REVENANT, "Two thirds switches to Revenant")
	_check(RULE.tier(50.01, 150) == RULE.Tier.REVENANT, "Above one third remains Revenant")
	_check(RULE.tier(50, 150) == RULE.Tier.BRUTE, "One third switches to Brute")
	var stage := Node3D.new()
	root.add_child(stage)
	var effects := Node3D.new()
	stage.add_child(effects)
	var target := Target.new()
	stage.add_child(target)
	target.position = Vector3(0, 1, -15)
	var horde := HORDE.instantiate() as CharacterBody3D
	horde.position.y = 1.365
	stage.add_child(horde)
	horde.set_physics_process(false)
	horde.set_target(target)
	horde.configure_world(effects, null)
	_check(horde.get_node("Body").scale.is_equal_approx(Vector3.ONE * 2.21), "Horde grows another 30 percent in XYZ")
	var capsule: CapsuleShape3D = horde.get_node("CollisionShape3D").shape
	_check(is_equal_approx(capsule.radius, 1.365) and is_equal_approx(capsule.height, 2.73), "Collision scales with the visual")
	var previous: Array[Node3D] = []
	for entry in [[150.0, "infected_hunger.tscn"], [100.0, "infected_revenant.tscn"], [50.0, "infected_brute.tscn"], [25.0, "infected_brute.tscn"]]:
		horde.health = float(entry[0])
		horde._enter(0)
		horde._summon_cooldown = 0.0
		horde._behaviour_tick(0.02, target.position - horde.position)
		_check(int(horde.state) == 4, "Living earlier waves do not block the next summon")
		horde._release_summon()
		var wave: Array[Node3D] = []
		for child in stage.get_children():
			if child.has_meta("summoned_by") and child not in previous:
				wave.append(child)
		_check(wave.size() == 3, "Every wave adds three infected even beyond six alive")
		for child in wave:
			_check(child.scene_file_path.get_file() == str(entry[1]), "Health selects the expected species")
			_check(child.effects_root == effects and child._target == target, "Summons receive world and target wiring")
			var shape: CapsuleShape3D = child.get_node("CollisionShape3D").shape
			_check(is_equal_approx(child.position.y - shape.height * 0.5, 0.02), "Every species spawns on the same floor")
			child.set_physics_process(false)
		for child in previous:
			_check(not child.is_dead(), "Earlier summons stay alive")
		previous.append_array(wave)
	await _test_blocked_spawn(stage, horde, previous.size())
	horde.health = 0.0
	horde._release_summon()
	_check(_summoned_count(stage) == previous.size(), "Dead Horde cannot release pending waves")
	var old := LEGACY.instantiate()
	stage.add_child(old)
	_check(not FileAccess.file_exists("res://models/objects/characters/mutant_animated.glb"), "Retired mutant model is absent")
	_check(old.get_node("Body/Visual").scene_file_path.ends_with("Brute_rig.tscn"), "Old map scene path uses the current rig")
	stage.queue_free()
	await process_frame
	print("Horde escalation tests: %d failure(s)." % failures)
	quit(failures)


func _test_blocked_spawn(stage: Node3D, horde: CharacterBody3D, before: int) -> void:
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 10, 20)
	shape.shape = box
	blocker.add_child(shape)
	stage.add_child(blocker)
	await physics_frame
	horde._release_summon()
	_check(_summoned_count(stage) == before, "Blocked capsules are skipped instead of spawning inside geometry")
	blocker.queue_free()
	await process_frame


func _summoned_count(stage: Node) -> int:
	var count := 0
	for child in stage.get_children():
		if child.has_meta("summoned_by"):
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
