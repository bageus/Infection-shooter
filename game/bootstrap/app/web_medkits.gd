extends RefCounted
## Medkits in a run (web arena and debug builds): stock is taken at the start (shop stock on web maps,
## five free ones in debug), the HUD button next to the antidote icon (or the H key) spends one for
## +100 health. The button shows only while "active medkit use" is on in the settings. Unspent
## web medkits go back to the shop when the run ends.
const SHOP := preload("res://game/bootstrap/app/web_shop.gd")
const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
const MAP_MODE := preload("res://game/bootstrap/app/planning_map_mode.gd")
const HEAL := 100.0
const DEBUG_STOCK := 5
const META := &"medkits"
const FROM_SHOP := &"medkits_from_shop"


## Called once when a run starts; builds the HUD button when the run has medkits.
static func begin(main: Node) -> void:
	if main.has_meta(META):
		return
	var web := MAP_MODE.is_web()
	if not web and not OS.is_debug_build():
		return
	var count := DEBUG_STOCK
	if web:
		var supplies: Dictionary = WALLET.profile()["supplies"]
		count = mini(int(supplies.get("health", 0)), SHOP.SUPPLY_CAP)
		supplies["health"] = int(supplies.get("health", 0)) - count
		WALLET.mark_dirty()
	main.set_meta(META, count)
	main.set_meta(FROM_SHOP, web)
	var button := preload("res://game/bootstrap/app/web_medkit_button.gd").new()
	main.add_child(button)
	button.call("setup", main)


## Spends one medkit if the hero is hurt; true when it healed.
static func use(main: Node) -> bool:
	var player: Node = main.get("player")
	var left := int(main.get_meta(META, 0))
	if left <= 0 or not is_instance_valid(player) or float(player.get("health")) <= 0.0 \
			or float(player.get("health")) >= float(player.get("max_health")):
		return false
	main.set_meta(META, left - 1)
	player.call("heal", HEAL, &"medkit")
	player.call("play_item_sound", &"medkit_use")
	return true


## Unspent shop medkits return to the stock; safe to call twice.
static func end(main: Node) -> void:
	if not main.has_meta(META):
		return
	if bool(main.get_meta(FROM_SHOP, false)):
		var supplies: Dictionary = WALLET.profile()["supplies"]
		supplies["health"] = mini(int(supplies.get("health", 0)) + int(main.get_meta(META)), SHOP.SUPPLY_CAP)
		WALLET.mark_dirty()
	main.remove_meta(META)
