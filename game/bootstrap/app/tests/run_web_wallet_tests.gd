extends SceneTree
## Web arena wallet: kill prices, global coins that survive a reload, beaten arenas.

const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	WALLET.path = "user://web_progress_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	WALLET.reset_cache()
	_check(WALLET.coins() == 0, "a fresh wallet is empty")
	var kinds := ["hunger", "revenant", "brute", "titan", "colossus"]
	for index in kinds.size():
		_check(WALLET.price(kinds[index]) == index + 1, "price of %s is %d" % [kinds[index], index + 1])
	_check(WALLET.price("horde") == 100, "the Horde pays 100")
	WALLET.add_kill("hunger")
	WALLET.add_kill("brute")
	_check(WALLET.coins() == 4, "kills add up")
	WALLET.profile()["supplies"]["armor"] = 2
	WALLET.mark_dirty()
	WALLET.mark_beaten("office_1")
	WALLET.mark_beaten("office_1")
	WALLET.flush()
	WALLET.reset_cache()
	_check(WALLET.coins() == 4 and WALLET.profile()["supplies"]["armor"] == 2 and WALLET.is_beaten("office_1") and not WALLET.is_beaten("lab_1"), "coins and beaten arenas survive a reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	print("web wallet tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
