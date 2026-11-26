extends SceneTree
## Web arena hook: a killed infected pays its coins on web maps only; a Horde's summon pays nothing.

const ARENA := preload("res://game/bootstrap/app/web_arena.gd")
const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
const MODE := preload("res://game/bootstrap/app/planning_map_mode.gd")
const DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const BRUTE := preload("res://game/features/infected/public/infected_brute.tscn")
var failures := 0


class FakeMain extends Node:
	var enemies := Node3D.new()
	var _ended := false
	var _dying := false

	func _init() -> void:
		add_child(enemies)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	WALLET.path = "user://web_kill_coins_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	WALLET.reset_cache()
	var main := FakeMain.new()
	root.add_child(main)
	var director := DIRECTOR.new()
	main.add_child(director)
	director.configure(main.enemies, Node3D.new())
	var placed := HUNGER.instantiate() as Node3D
	main.enemies.add_child(placed)
	ARENA.sync(main, director, "")
	var spawned := BRUTE.instantiate() as Node3D
	main.enemies.add_child(spawned)
	var summoned := HUNGER.instantiate() as Node3D
	summoned.set_meta("summoned_by", 1)
	main.enemies.add_child(summoned)
	await process_frame
	MODE.restore(null, "")
	placed.call("take_damage", 99999.0)
	_check(WALLET.coins() == 0, "campaign map: no coins")
	MODE.restore(null, "web")
	spawned.call("take_damage", 99999.0)
	summoned.call("take_damage", 99999.0)
	await process_frame
	_check(WALLET.coins() == 3, "a killed brute pays 3, the summon pays nothing")
	_check(main.has_meta(&"web_coins_label"), "the coin counter shows")
	MODE.restore(null, "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	print("web kill coins tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
