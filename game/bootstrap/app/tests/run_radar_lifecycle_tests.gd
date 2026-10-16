extends SceneTree
## A06: the public radar follows the real infected's alive/corpse lifecycle.
const RADAR := preload("res://game/presentation/prototype_hud/public/radar.tscn")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const BUDGET := preload("res://game/features/infected/public/corpse_budget.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := Node3D.new()
	player.name = "Player"
	stage.add_child(player)
	var enemies := Node3D.new()
	enemies.name = "Enemies"
	stage.add_child(enemies)
	var layer := RADAR.instantiate()
	var radar := layer.get_node("Radar") as Control
	radar.set("player_path", NodePath("../../Player"))
	radar.set("enemies_path", NodePath("../../Enemies"))
	stage.add_child(layer)
	var enemy := HUNGER.instantiate() as CharacterBody3D
	enemy.position = Vector3(2, 1, 3)
	enemy.set("death_linger_seconds", .03)
	enemy.call("configure_world", enemies, null)
	enemies.add_child(enemy)
	enemy.set_physics_process(false)
	await physics_frame
	_check(_target(radar, enemy), "A real living Hunger is a radar target")
	enemy.hide()
	_check(not _target(radar, enemy), "Intentionally hidden live infected is not shown")
	enemy.show()
	_check(_target(radar, enemy), "Showing a living infected restores its marker")
	await _death_and_eviction(radar, enemy, enemies)
	var spawned := HUNGER.instantiate() as CharacterBody3D
	enemies.add_child(spawned)
	spawned.set_physics_process(false)
	_check(_target(radar, spawned), "Later spawns are included without a cached roster")
	spawned.queue_free()
	_check(not _target(radar, spawned), "Queued live infected is excluded before deletion")
	stage.queue_free()
	await process_frame
	await process_frame
	BUDGET.keep = false
	_check(BUDGET.count() == 0, "Teardown releases retained corpse registrations")
	print("Radar lifecycle tests: %d failures" % failures)
	quit(1 if failures else 0)


func _death_and_eviction(radar: Control, enemy: CharacterBody3D, enemies: Node3D) -> void:
	var parts: Node = enemy.get("_parts")
	var severed: RigidBody3D = parts.call("sever", &"arm_l", Vector3.RIGHT)
	_check(severed != null and severed.get_parent() == enemies, "Real severed part shares the enemy container")
	if severed != null:
		_check(not _target(radar, severed), "A severed part cannot produce a radar marker")
	BUDGET.keep = true
	enemy.call("take_projectile_damage", 1000.0, enemy.global_position, Vector3.FORWARD, "PISTOL")
	_check(enemy.call("is_dead") and enemy.get_parent() == enemies, "Killed infected stays in the same container")
	_check(not _target(radar, enemy), "Marker disappears immediately on death")
	await create_timer(.2).timeout
	_check(BUDGET.count() == 1, "Real corpse entered the retention budget")
	_check((enemy.get("body_visual") as Node3D).visible, "Retained corpse is still visible")
	_check(not _target(radar, enemy), "Visible retained corpse is not a live target")
	for index in BUDGET.MAX_CORPSES:
		var replacement := Node3D.new()
		enemies.add_child(replacement)
		BUDGET.retain(replacement, null, replacement.hide)
	_check(not (enemy.get("body_visual") as Node3D).visible, "Budget evicts and hides the original corpse")
	_check(not _target(radar, enemy), "Evicted corpse stays excluded")


func _target(radar: Control, node: Node) -> bool:
	return bool(radar.call("_is_radar_target", node))


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
