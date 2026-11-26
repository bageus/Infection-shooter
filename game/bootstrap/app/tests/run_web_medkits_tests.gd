extends SceneTree
## Run medkits: shop stock is taken, spent one per use only when hurt, the rest goes back.

const MEDKITS := preload("res://game/bootstrap/app/web_medkits.gd")
const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
const MODE := preload("res://game/bootstrap/app/planning_map_mode.gd")
var failures := 0


class FakePlayer extends Node:
	var health := 40.0
	var max_health := 100.0

	func heal(amount: float, _source: StringName = &"") -> float:
		health = minf(max_health, health + amount)
		return amount

	func play_item_sound(_event: StringName) -> void:
		pass


class FakeMain extends Node:
	var player: Node


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	WALLET.path = "user://web_progress_medkit_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	WALLET.reset_cache()
	MODE.current = "web"
	WALLET.profile()["supplies"]["health"] = 3
	var main := FakeMain.new()
	main.player = FakePlayer.new()
	MEDKITS.begin(main)
	_check(int(main.get_meta(MEDKITS.META)) == 3 and WALLET.profile()["supplies"]["health"] == 0, "the run takes the stocked medkits")
	MEDKITS.begin(main)
	_check(int(main.get_meta(MEDKITS.META)) == 3, "begin runs once")
	_check(MEDKITS.use(main) and main.player.health == 100.0, "a hurt hero is healed by 100")
	_check(not MEDKITS.use(main) and int(main.get_meta(MEDKITS.META)) == 2, "a full hero keeps the medkit")
	main.player.health = 10.0
	MEDKITS.use(main)
	MEDKITS.end(main)
	MEDKITS.end(main)
	_check(WALLET.profile()["supplies"]["health"] == 1, "one unspent medkit returns to the shop")
	main.player.free()
	main.free()
	MODE.current = "campaign"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	print("web medkits tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
