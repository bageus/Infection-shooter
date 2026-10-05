extends SceneTree

const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
const BODY := preload("res://assets/interface/fonts/body.ttf")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0
var original_settings := PackedByteArray()
var had_settings := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	had_settings = FileAccess.file_exists(PREFS.FILE)
	if had_settings:
		original_settings = FileAccess.get_file_as_bytes(PREFS.FILE)
	var frontend := FRONT.instantiate()
	root.add_child(frontend)
	current_scene = frontend
	await process_frame
	var menu: Control = frontend.get_node("Menu")
	_check(menu.get("screen_kind") == "main" and not paused, "entry opens main menu")
	_check(menu.get("buttons")[1].disabled, "campaign continue is unavailable without a save")
	var title_area := menu.get("content").get_child(0) as Control
	_check(title_area.size.y >= (title_area.get_child(0) as Label).get_minimum_size().y, "condensed title reserves both lines without overlap")
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_DOWN
	menu.call("_input", event)
	_check(root.gui_get_focus_owner() == menu.get("buttons")[2], "keyboard skips unavailable continue")
	menu.call("activate", "settings")
	await process_frame
	var dialog: Control = menu.get("modal")
	dialog.call("_language_changed", 1)
	dialog.call("_scale_changed", 2)
	await process_frame
	_check(menu.call("text", "new") == "New operation", "English menu applies immediately")
	var saved = PREFS.new()
	saved.load_settings()
	_check(saved.values.language == "en" and is_equal_approx(saved.values.text_scale, 1.3), "settings persist")
	_check(menu.get("content_scroll").get_rect().end.y < menu.size.y - 20, "130 percent menu stays inside its scroll viewport")
	_check(dialog.is_ancestor_of(root.gui_get_focus_owner()), "dialog owns focus")
	event.keycode = KEY_ESCAPE
	menu.call("_input", event)
	_check(menu.get("modal") == null, "Escape closes settings")
	menu.call("activate", "briefing")
	_check(menu.get("modal") != null, "new operation opens real briefing")
	menu.call("dispatch", "start")
	await process_frame
	await process_frame
	var app: Node = current_scene
	_check(app.scene_file_path == "res://game/bootstrap/app/main.tscn", "deployment loads combat scene")
	_test_gameplay_font(app)
	_test_settings_reach_game(app)
	await _test_pause_and_planner(app)
	await _test_results_and_return(app)
	_restore_settings()
	print("Menu integration tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _test_gameplay_font(app: Node) -> void:
	var hp := app.get_node("PrototypeHUD/HealthPanel/HealthValue") as Label
	_check(_is_body_font(hp.get_theme_font("font")), "combat HUD uses supplied menu body font")
	var title := app.get_node("PlanningUI/Panel/VBox/Title") as Label
	_check(_is_body_font(title.get_theme_font("font")), "planner uses same font")
	var tree: CanvasLayer = app.get("mutation_tree_ui")
	var points: Label = tree.get("points_label")
	_check(_is_body_font(points.get_theme_font("font")), "mutation tree uses same font")
	for hint: Label3D in app.find_children("*", "Label3D", true, false):
		_check(hint.font == BODY, "world hint uses same font: " + hint.text)


func _is_body_font(font: Font) -> bool:
	return font is FontFile and (font as FontFile).data == BODY.data


func _test_pause_and_planner(app: Node) -> void:
	app.call("_open_pause_menu")
	var pause: Control = app.get("pause_menu")
	_check(paused and pause.visible and app.get("_pause_open"), "pause menu freezes simulation")
	var gameplay_key := InputEventKey.new()
	gameplay_key.pressed = true
	gameplay_key.keycode = KEY_M
	root.push_input(gameplay_key)
	await process_frame
	_check(not app.get("mutation_tree_ui").call("is_tree_open"), "pause consumes mutation-tree shortcut behind menu")
	_check(pause.get("buttons")[1].text == "PLANNING MODE", "planner entry is in pause menu")
	var infection := app.get_node("Gameplay/Player/InfectionRuntime")
	var mutation_before := float(infection.call("get_mutation"))
	await create_timer(0.1).timeout
	_check(is_equal_approx(infection.call("get_mutation"), mutation_before), "infection stops while paused")
	pause.call("activate", "settings")
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	pause.call("_input", event)
	_check(paused and pause.visible, "closing pause settings keeps game paused")
	pause.call("_input", event)
	_check(not paused and not pause.visible, "second Escape resumes simulation")
	app.call("_open_pause_menu")
	pause.get("buttons")[1].pressed.emit()
	var planner: Node = app.get("planning_mode")
	_check(planner.get("active") and paused and not pause.visible, "planner button enters existing editor")
	_check(app.get_node("PlanningUI").visible, "planner UI is visible")
	_check(not app.get_node("PrototypeHUD").visible, "planner hides combat HUD")
	planner.call("exit")
	_check(not paused and not planner.get("active"), "planner exits to playable game")
	await process_frame


func _test_results_and_return(app: Node) -> void:
	app.call("_end_run", "MUTATION OVERTOOK YOU")
	var result: Control = app.get("game_over")
	_check(paused and result.visible and result.get("screen_kind") == "failed", "mutation defeat opens failure artwork")
	_check(result.get("reason_key") == "failedMutation", "defeat reason is localized")
	_check(result.get("buttons")[0].disabled, "checkpoint is honestly unavailable")
	app.call("_end_run", "MISSION COMPLETE")
	_check(result.get("screen_kind") == "complete", "floor goal uses success artwork")
	_check(result.call("text", "samples") == "Floor", "success describes current floor instead of campaign extraction")
	result.call("dispatch", "restart")
	await process_frame
	await process_frame
	app = current_scene
	_check(not paused and not app.get("_ended"), "restart restores active combat")
	app.call("_open_pause_menu")
	var pause: Control = app.get("pause_menu")
	pause.call("activate", "main")
	_check(pause.get("modal") != null, "leaving current attempt requires in-game confirmation")
	pause.call("dispatch", "main")
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == FRONT.resource_path and not paused, "return opens main menu and clears pause")


# Volume, sound and brightness act on the running game, not only the menu.
func _test_settings_reach_game(app: Node) -> void:
	var prefs = PREFS.new()
	prefs.values.volume = 0.2
	prefs.values.brightness = 1.3
	prefs.apply_to_game(app.get_tree())
	var master := AudioServer.get_bus_index(&"Master")
	_check(AudioServer.get_bus_volume_db(master) < -5.0, "menu volume lowers the game's master bus")
	var world := app.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_check(world != null and world.environment.adjustment_enabled and is_equal_approx(world.environment.adjustment_brightness, 1.3), "brightness reaches the game scene")
	prefs.values.sound = false
	prefs.apply_to_game(app.get_tree())
	_check(AudioServer.is_bus_mute(master), "turning sound off mutes the game")
	prefs.reset()
	prefs.apply_to_game(app.get_tree())
	_check(not AudioServer.is_bus_mute(master) and absf(AudioServer.get_bus_volume_db(master)) < 0.01, "default settings keep the authored mix")


func _restore_settings() -> void:
	if had_settings:
		var file := FileAccess.open(PREFS.FILE, FileAccess.WRITE)
		file.store_buffer(original_settings)
	else:
		DirAccess.remove_absolute(PREFS.FILE)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
