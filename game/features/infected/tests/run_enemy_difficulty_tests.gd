extends SceneTree
## Enemy difficulty: low halves the authored health and damage, normal keeps them, high uses the editor maximum.

const AUTHORING := preload("res://game/features/infected/infected_authoring.gd")
const DIFFICULTY := preload("res://game/features/infected/public/enemy_difficulty.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_percent_per_level()
	_test_stats_follow_level()
	_test_reapply_does_not_compound()
	print("Enemy difficulty tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _enemy() -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar max_health := 100.0\nvar health := 100.0\nvar attack_damage := 10.0\nvar obstacle_damage := 5.0\n"
	script.reload()
	var enemy := Node.new()
	enemy.set_script(script)
	return enemy


func _test_percent_per_level() -> void:
	DIFFICULTY.level = DIFFICULTY.LOW
	_check(is_equal_approx(DIFFICULTY.percent(200.0), 100.0), "Low halves an authored 200")
	_check(is_equal_approx(DIFFICULTY.percent(100.0), 50.0), "Low halves the default 100")
	DIFFICULTY.level = DIFFICULTY.NORMAL
	_check(is_equal_approx(DIFFICULTY.percent(200.0), 200.0), "Normal keeps the authored value")
	DIFFICULTY.level = DIFFICULTY.HIGH
	_check(is_equal_approx(DIFFICULTY.percent(50.0), 200.0), "High uses the editor maximum")
	DIFFICULTY.level = DIFFICULTY.NORMAL


func _test_stats_follow_level() -> void:
	var enemy := _enemy()
	var authoring = AUTHORING.new(enemy)
	DIFFICULTY.level = DIFFICULTY.LOW
	authoring.set_stats({"health": 200.0, "damage": 200.0})
	_check(is_equal_approx(enemy.max_health, 100.0), "Low gives health 100 from authored 200")
	_check(is_equal_approx(enemy.attack_damage, 10.0), "Low gives damage 10 from base 10 at 100%")
	_check(is_equal_approx(enemy.obstacle_damage, 5.0), "Low halves obstacle damage too")
	DIFFICULTY.level = DIFFICULTY.HIGH
	authoring.set_stats({"health": 50.0, "damage": 50.0})
	_check(is_equal_approx(enemy.max_health, 200.0), "High gives 200% health")
	_check(is_equal_approx(enemy.attack_damage, 20.0), "High gives 200% damage")
	DIFFICULTY.level = DIFFICULTY.NORMAL
	authoring.set_stats({"health": 200.0, "damage": 200.0})
	_check(is_equal_approx(enemy.max_health, 200.0), "Normal keeps the authored health")
	_check(is_equal_approx(enemy.attack_damage, 20.0), "Normal keeps the authored damage")
	_check(is_equal_approx(authoring.damage_percent(), 200.0), "Normal reports the authored damage percent")
	enemy.free()


func _test_reapply_does_not_compound() -> void:
	var enemy := _enemy()
	var authoring = AUTHORING.new(enemy)
	DIFFICULTY.level = DIFFICULTY.LOW
	authoring.set_stats({"health": 200.0, "damage": 200.0})
	authoring.apply_saved_stats()
	authoring.set_stats(authoring.stats())
	_check(is_equal_approx(enemy.max_health, 100.0), "Reapplying low does not halve again")
	DIFFICULTY.level = DIFFICULTY.NORMAL
	enemy.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
