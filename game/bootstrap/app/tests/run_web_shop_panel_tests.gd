extends SceneTree
## Web shop panel in the main menu: shown only where the platform has the shop, buying changes the saved profile.

const SCREEN := preload("res://game/bootstrap/app/menu/menu_screen.gd")
const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	call_deferred("_run")


func _buttons(node: Node, found: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			found.append(child)
		_buttons(child, found)


func _run() -> void:
	WALLET.path = "user://web_shop_panel_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	WALLET.reset_cache()
	root.size = Vector2i(1280, 720)
	var menu := Control.new()
	menu.set_script(SCREEN)
	root.add_child(menu)
	menu.get("preferences").values.language = "ru"
	_check(menu.shop == null, "no shop on a platform without the endless mode")
	menu.shop_enabled = true
	menu.refresh()
	await process_frame
	_check(is_instance_valid(menu.shop), "the shop shows on the main menu")
	var all: Array[Button] = []
	_buttons(menu.shop, all)
	var pistol_pack := all.filter(func(b: Button) -> bool: return b.text.contains("80"))
	_check(not pistol_pack.is_empty(), "the pistol pack costs 80")
	pistol_pack[0].pressed.emit()
	_check(WALLET.profile()["ammo"].is_empty(), "too few coins: nothing is bought")
	WALLET.profile()["coins"] = 500
	menu.refresh()
	await process_frame
	all.clear()
	_buttons(menu.shop, all)
	all.filter(func(b: Button) -> bool: return b.text.contains("80"))[0].pressed.emit()
	await process_frame
	_check(WALLET.profile()["ammo"].get("pistol", 0) == 60 and WALLET.coins() == 420, "the pack is bought: +60 ammo, -80 coins")
	menu.set("screen_kind", "pause")
	menu.refresh()
	await process_frame
	_check(menu.shop == null, "no shop outside the main menu")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	print("web shop panel tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
