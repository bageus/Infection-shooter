extends SceneTree
## Weapons and the control threshold travel to the next map; invalid carry data is ignored.

const MAIN := preload("res://game/bootstrap/app/main.tscn")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 5:
		await process_frame
	var player: Node = game.get("player")
	var runtime: Node = game.get("infection_runtime")
	var slots: Array = player.call("export_loadout").slots
	_check(slots.size() == 3, "three weapon slots")
	_check(slots == [0, -1, -1], "a new game starts with the pistol only")
	_check(not bool(player.call("select_weapon_slot", 1)), "empty slot cannot be selected")
	_check(bool(player.call("pickup_weapon", 3)) and player.call("export_loadout").slots == [0, 3, -1], "pickup fills the first empty slot")
	var other := [0, 2, -1]
	player.call("import_loadout", {"slots": other})
	_check(player.call("export_loadout").slots == other, "loadout imported")
	player.call("import_loadout", {"slots": [0, 0, 1]})
	player.call("import_loadout", {"slots": [-1, 1, 2]})
	player.call("import_loadout", {"slots": [99, 1, 2]})
	_check(player.call("export_loadout").slots == other, "invalid loadouts ignored")
	runtime.call("restore_critical_threshold", 45.0)
	_check(is_equal_approx(runtime.call("get_critical_threshold"), 45.0), "threshold restored")
	runtime.call("restore_critical_threshold", 5.0)
	_check(is_equal_approx(runtime.call("get_critical_threshold"), 30.0), "threshold clamped to base")
	game.call("apply_carry", {"loadout": {"slots": slots}, "threshold": 55.0})
	_check(player.call("export_loadout").slots == slots and is_equal_approx(runtime.call("get_critical_threshold"), 55.0), "apply_carry")
	_check(not bool(player.call("has_emergency_key")), "key stays reset")
	print("level carry tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
