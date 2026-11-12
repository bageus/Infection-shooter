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
	_test_every_type_keeps_order()
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
	_check(is_equal_approx(DIFFICULTY.percent(50.0), 100.0), "High doubles an authored 50")
	_check(is_equal_approx(DIFFICULTY.percent(200.0), 400.0), "High doubles an authored 200")
	_check(DIFFICULTY.percent(50.0) < DIFFICULTY.percent(200.0), "High keeps higher percent harder")
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
	_check(is_equal_approx(enemy.max_health, 100.0), "High gives 100% health from authored 50")
	_check(is_equal_approx(enemy.attack_damage, 10.0), "High gives 100% damage from authored 50")
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


## Every enemy scene must keep higher health and damage percents harder on every level.
func _test_every_type_keeps_order() -> void:
	for scene in ["infected_hunger", "infected_brute", "infected_colossus", "infected_titan", "infected_revenant", "infected_horde", "mutant_level2", "infected_capsule"]:
		for level in [DIFFICULTY.LOW, DIFFICULTY.NORMAL, DIFFICULTY.HIGH]:
			DIFFICULTY.level = level
			var low = load("res://game/features/infected/public/%s.tscn" % scene).instantiate()
			low.configure_stats({"health": 50.0, "damage": 50.0})
			var high = load("res://game/features/infected/public/%s.tscn" % scene).instantiate()
			high.configure_stats({"health": 200.0, "damage": 200.0})
			_check(low.max_health < high.max_health, "%s health order at level %d" % [scene, level])
			_check(low.attack_damage < high.attack_damage, "%s damage order at level %d" % [scene, level])
			low.free()
			high.free()
	DIFFICULTY.level = DIFFICULTY.NORMAL


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
