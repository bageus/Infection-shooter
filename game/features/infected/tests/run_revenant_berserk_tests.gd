extends SceneTree
## Revenant berserk: kills nearby are counted once, far kills are ignored, and berserk
## scales speed and damage and adds the rage overlay.

const REVENANT := preload("res://game/features/infected/public/infected_revenant.tscn")
var failures := 0


class Corpse:
	extends Node3D
	var dead := false
	func is_dead() -> bool:
		return dead


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var revenant := REVENANT.instantiate() as CharacterBody3D
	stage.add_child(revenant)
	revenant.global_position = Vector3.ZERO
	await process_frame

	revenant.set_physics_process(false) # Only the explicit scans below count kills.
	var corpses: Array[Corpse] = []
	for i in 4:
		var enemy := Corpse.new()
		enemy.add_to_group("infected_alive")
		stage.add_child(enemy)
		enemy.global_position = Vector3(2.0 + i * 0.5, 0.0, 1.0)
		corpses.append(enemy)
	var far := Corpse.new()
	far.add_to_group("infected_alive")
	stage.add_child(far)
	far.global_position = Vector3(30.0, 0.0, 0.0)
	await process_frame

	revenant.call("_scan_kills")
	_check(revenant.get("_known").size() == 4, "Only the four nearby enemies are remembered.")
	# Chance 1 with four kills: the fourth death starts berserk, the first three do not.
	revenant.set("berserk_chance", 1.0)
	revenant.set("_kills_needed", 4)
	corpses[0].dead = true
	corpses[0].remove_from_group("infected_alive")
	revenant.call("_scan_kills")
	revenant.call("_scan_kills")
	_check(int(revenant.get("_kills_seen")) == 1, "A nearby death is counted once, not again on the next scan.")
	for enemy in corpses.slice(1, 3):
		enemy.dead = true
		enemy.remove_from_group("infected_alive")
	revenant.call("_scan_kills")
	_check(not bool(revenant.get("berserk")) and int(revenant.get("_kills_seen")) == 3, "Three kills of four needed do not start berserk.")
	corpses[3].dead = true
	corpses[3].remove_from_group("infected_alive")
	revenant.call("_scan_kills")
	_check(bool(revenant.get("berserk")), "The fourth nearby death starts berserk when the chance is 1.")

	# Chance 0 with three kills needed: the roll fails, the count restarts and a new threshold is rolled.
	var second := REVENANT.instantiate() as CharacterBody3D
	stage.add_child(second)
	second.global_position = Vector3(0.0, 0.0, 0.0)
	second.set_physics_process(false)
	await process_frame
	second.set("berserk_chance", 0.0)
	second.set("_kills_needed", 3)
	var fresh: Array[Corpse] = []
	for i in 3:
		var enemy := Corpse.new()
		enemy.add_to_group("infected_alive")
		stage.add_child(enemy)
		enemy.global_position = Vector3(1.0 + i * 0.5, 0.0, 1.0)
		fresh.append(enemy)
	second.call("_scan_kills")
	for enemy in fresh:
		enemy.dead = true
		enemy.remove_from_group("infected_alive")
	second.call("_scan_kills")
	_check(not bool(second.get("berserk")), "A failed roll does not start berserk.")
	_check(int(second.get("_kills_seen")) == 0, "A failed roll restarts the kill count.")
	var needed := int(second.get("_kills_needed"))
	_check(needed >= 3 and needed <= 4, "A failed roll rolls the next threshold as 3 or 4.")
	second.queue_free()

	var base_speed: float = revenant.get("move_speed")
	var base_damage: float = revenant.get("attack_damage")
	revenant.call("_start_berserk")
	_check(bool(revenant.get("berserk")), "Berserk turns on.")
	_check(is_equal_approx(float(revenant.get("move_speed")), base_speed * 1.5), "Berserk raises move speed by half.")
	_check(is_equal_approx(float(revenant.get("attack_damage")), base_damage * 1.5), "Berserk raises attack damage by half.")
	var overlays := 0
	for mesh in revenant.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).material_overlay != null:
			overlays += 1
	_check(overlays > 0, "Berserk shows the rage overlay on the body.")

	far.queue_free()
	stage.queue_free()
	print("Revenant berserk tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
