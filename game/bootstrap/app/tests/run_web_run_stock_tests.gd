extends SceneTree
## A web run starts from the shop stock and returns unspent ammo: weapons, ammo that fits, antidotes, armor.

const ARENA := preload("res://game/bootstrap/app/web_arena.gd")
const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
const MODE := preload("res://game/bootstrap/app/planning_map_mode.gd")
var failures := 0


class FakeGun extends Node:
	var reserve := 10
	var capacity := 100

	func carried_ammo() -> int:
		return reserve

	func add_reserve_ammo(amount: int) -> int:
		var before := reserve
		reserve = mini(capacity, reserve + amount)
		return reserve - before


class FakePlayer extends Node:
	var weapons: Array = []
	var held: Array[int] = [0]
	var antidotes := 2
	var max_antidotes := 5
	var armor := 0.0
	var max_armor := 100.0

	func pickup_weapon(index: int) -> bool:
		held.append(index)
		return true

	func carried_weapon_indices() -> Array[int]:
		return held

	func add_antidote(amount: int) -> bool:
		antidotes = mini(max_antidotes, antidotes + amount)
		return true


class FakeMain extends Node:
	var player := FakePlayer.new()

	func _init() -> void:
		add_child(player)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	WALLET.path = "user://web_run_stock_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	WALLET.reset_cache()
	var main := FakeMain.new()
	for index in 8:
		var gun := FakeGun.new()
		main.player.weapons.append(gun)
		main.player.add_child(gun)
	var profile := WALLET.profile()
	profile["owned"] = ["shotgun"]
	profile["rented"] = ["ak"]
	profile["ammo"] = {"pistol": 150, "shotgun": 24, "rifle": 90}
	profile["supplies"] = {"antidote": 5, "armor": 3}
	MODE.restore(null, "")
	ARENA.begin_run(main)
	_check(main.player.held == [0] and profile["ammo"]["pistol"] == 150, "a campaign map ignores the stock")
	MODE.restore(null, "web")
	ARENA.begin_run(main)
	_check(main.player.held == [0, 4, 2] and profile["rented"].is_empty(), "rented AK then the owned shotgun are equipped")
	_check(main.player.weapons[0].reserve == 100 and profile["ammo"]["pistol"] == 60, "pistol ammo fills to capacity, the rest stays in stock")
	_check(main.player.weapons[4].reserve == 100 and main.player.weapons[2].reserve == 34, "rifle and shotgun ammo go to the held weapons")
	_check(main.player.antidotes == 5 and profile["supplies"]["antidote"] == 2, "antidotes top up to the maximum")
	_check(main.player.armor == 100.0 and profile["supplies"]["armor"] == 1, "armor plates are used up to the maximum")
	main.player.weapons[0].reserve = 50 # spent 50 of the 90 taken
	ARENA.end_run(main)
	_check(profile["ammo"]["pistol"] == 100, "unspent ammo (40 of 90 taken) returns to the stock")
	ARENA.end_run(main)
	_check(profile["ammo"]["pistol"] == 100, "ending twice returns nothing more")
	MODE.restore(null, "")
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	print("web run stock tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
