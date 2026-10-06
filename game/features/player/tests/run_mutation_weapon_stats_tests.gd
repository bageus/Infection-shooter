extends SceneTree
const EFFECTS := preload("res://game/features/player/mutation_skill_effects.gd")
var failures := 0


class Host extends CharacterBody3D:
	var max_health := 100.0
	var health := 100.0

	func heal(amount: float) -> float:
		var gained := minf(amount, max_health - health)
		health += gained
		return gained


class Runtime extends Node:
	signal skill_cast(skill_id: String)
	signal tree_changed
	signal mutation_changed(amount: float, threshold: float)
	var skills: Dictionary = {}

	func has_skill(skill_id: String) -> bool:
		return skills.has(skill_id)


class Weapon extends Node3D:
	var writes := 0
	var reload_time := 2.0:
		set(value):
			reload_time = value
			writes += 1
	var spread_degrees := 10.0:
		set(value):
			spread_degrees = value
			writes += 1
	var shots_per_second := 4.0:
		set(value):
			shots_per_second = value
			writes += 1
	var bullet_damage := 20.0:
		set(value):
			bullet_damage = value
			writes += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Host.new()
	root.add_child(host)
	var runtime := Runtime.new()
	host.add_child(runtime)
	var weapon := Weapon.new()
	host.add_child(weapon)
	var effects := EFFECTS.new()
	host.add_child(effects)
	effects.set_process(false)
	var guns: Array[Node3D] = [weapon]
	effects.configure(host, runtime, guns)
	var initial := weapon.writes
	for frame in 20:
		effects.call("_process", .01)
	_check(weapon.writes == initial, "Idle frames do not rewrite weapon properties")
	runtime.skills["muscle_memory"] = true
	runtime.tree_changed.emit()
	_check(is_equal_approx(weapon.reload_time, 1.6), "Learning a passive immediately recalculates weapon stats")
	initial = weapon.writes
	runtime.mutation_changed.emit(40.0, 45.0)
	_check(weapon.writes == initial, "Mutation changes with identical modifiers do not rewrite weapons")
	runtime.skill_cast.emit("overload")
	effects.call("_process", 0.0)
	_check(is_equal_approx(weapon.reload_time, 1.04) and is_equal_approx(weapon.shots_per_second, 5.0), "Starting Overload applies existing reload/fire modifiers")
	initial = weapon.writes
	effects.call("_process", 1.0)
	_check(weapon.writes == initial, "Active buff countdown does not rewrite unchanged stats")
	effects.call("_process", 5.1)
	_check(is_equal_approx(weapon.reload_time, 1.6) and is_equal_approx(weapon.shots_per_second, 4.0), "Buff expiry restores the passive-adjusted baseline")
	runtime.skills.erase("muscle_memory")
	runtime.tree_changed.emit()
	_check(is_equal_approx(weapon.reload_time, 2.0), "Losing a passive restores its original baseline")
	_kill_and_roll_buffs(effects, runtime, weapon)
	host.queue_free()
	await process_frame
	print("Mutation weapon stats tests: %d failures" % failures)
	quit(failures)


func _kill_and_roll_buffs(effects: Node, runtime: Runtime, weapon: Weapon) -> void:
	var victim := Node3D.new()
	root.add_child(victim)
	runtime.skills["combat_reflex"] = true
	runtime.skills["battle_metabolism"] = true
	effects.call("on_enemy_killed", victim)
	effects.call("_process", 0.0)
	_check(is_equal_approx(weapon.shots_per_second, 4.88) and is_equal_approx(weapon.bullet_damage, 23.6), "Kill buffs immediately apply their existing multipliers")
	var initial := weapon.writes
	effects.call("on_enemy_killed", victim)
	effects.call("_process", 0.0)
	_check(weapon.writes == initial, "Refreshing a kill buff does not rewrite identical stats")
	effects.call("_process", 6.1)
	runtime.skills["reflex_arc"] = true
	effects.call("on_roll")
	effects.call("_process", 0.0)
	_check(is_equal_approx(weapon.shots_per_second, 4.8), "Roll buff changes fire rate")
	effects.call("_process", 3.1)
	_check(is_equal_approx(weapon.shots_per_second, 4.0), "Roll buff expiry restores fire rate")
	victim.queue_free()


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
