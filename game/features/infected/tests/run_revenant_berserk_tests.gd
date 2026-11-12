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
	corpses[0].dead = true
	corpses[0].remove_from_group("infected_alive")
	revenant.call("_scan_kills")
	_check(int(revenant.get("_kills_seen")) == 1, "A nearby death is counted once.")
	revenant.call("_scan_kills")
	_check(int(revenant.get("_kills_seen")) == 1, "A death is not counted again on the next scan.")

	for enemy in corpses.slice(1):
		enemy.dead = true
		enemy.remove_from_group("infected_alive")
	revenant.call("_scan_kills")
	# Berserk starts, or a failed roll at kill 3 reset the count and kill 4 is already counted (seen 1).
	var needed := int(revenant.get("_kills_needed"))
	_check(bool(revenant.get("berserk")) or (int(revenant.get("_kills_seen")) <= 1 and needed >= 3 and needed <= 4),
		"Four nearby deaths either start berserk or restart the count.")

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
