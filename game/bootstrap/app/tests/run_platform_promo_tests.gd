extends SceneTree
## The Steam promo button on the end screens and the per-platform ads/promo flags.

const CONFIG := preload("res://game/bootstrap/app/campaign_config.gd")
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
var failures := 0
var _requested: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _on_action(action: String) -> void:
	_requested.append(action)


func _has_steam(screen: Control) -> bool:
	return _steam_button(screen) != null


func _steam_button(screen: Control) -> Button:
	for button: Button in screen.get("buttons"):
		if button.name == "Steam":
			return button
	return null


func _run() -> void:
	var config := CONFIG.new()
	config.load_file()
	_check(config.shows_ads("yandex") and not config.shows_ads("itch") and not config.shows_ads("desktop"), "only yandex shows ads")
	_check(config.steam_promo_url("yandex").begins_with("https://") and config.steam_promo_url("itch") == "", "only yandex promotes Steam")
	var frontend := FRONT.instantiate()
	root.add_child(frontend)
	current_scene = frontend
	await process_frame
	var screen: Control = frontend.get_node("Menu")
	_check(screen.get("steam_url") == "", "the editor run is not a yandex build, so no promo")
	for kind in ["failed", "complete"]:
		screen.call("show_screen", kind)
		_check(not _has_steam(screen), "%s screen has no Steam button without a url" % kind)
	screen.set("steam_url", "https://store.steampowered.com/app/1")
	for kind in ["failed", "complete", "pause"]:
		screen.call("show_screen", kind)
		_check(_has_steam(screen) == (kind != "pause"), "%s screen Steam button follows the url" % kind)
	screen.connect("action_requested", _on_action)
	screen.call("show_screen", "failed")
	screen.call("dispatch", "steam")
	_check(_requested == ["steam"], "the button asks for the steam action")
	frontend.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("platform promo tests passed")
	quit(0)
