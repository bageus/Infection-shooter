extends SceneTree
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
const EFFECTS_QUALITY := preload("res://game/core/vfx/public/effects_quality.gd")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var had := FileAccess.file_exists(PREFS.FILE)
	var saved := FileAccess.get_file_as_bytes(PREFS.FILE) if had else PackedByteArray()
	var frontend := FRONT.instantiate()
	root.add_child(frontend)
	current_scene = frontend
	await process_frame
	var menu: Control = frontend.get_node("Menu")
	menu.preferences.reset()
	menu.refresh()
	_check(not menu.footer.visible, "Main has no quarantine footer")
	_check(menu.content.find_child("NoSave", true, false) != null, "No-save notice sits beside continue")
	_check(menu.text("noSave") == "Нет сохранения", "No campaign suffix")
	menu.activate("settings")
	await process_frame
	var dialog: Control = menu.modal
	var tabs: TabContainer = dialog.settings.tabs
	_check(tabs.get_tab_count() == 4, "Exactly four settings pages")
	_check(tabs.get_tab_title(0) == "Основные" and tabs.get_tab_title(3) == "Аудио", "Tabs have translated names")
	_check(tabs.get_child(0).find_child("Language", true, false) != null, "Language belongs to General")
	_check(tabs.get_child(2).find_child("Occlusion", true, false) != null, "Occlusion belongs to Video")
	_general_checks(tabs)
	var lighting := tabs.get_child(2).find_child("Lighting", true, false) as CheckButton
	_check(lighting != null and lighting.button_pressed, "Lighting belongs to Video and defaults on")
	lighting.set_pressed(false)
	var light_prefs := PREFS.new()
	light_prefs.load_settings()
	_check(not light_prefs.values.lighting, "Lighting toggle survives settings reload")
	lighting.set_pressed(true)
	_sunlight_checks(tabs, dialog)
	await _shadow_checks(tabs, dialog)
	_check(tabs.get_child(3).find_child("SoundToggle", true, false) != null, "Sound belongs to Audio")
	_slider_checks(tabs)
	_check_notice_badge(dialog, tabs)
	dialog.settings.notices._show(1)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	_check(dialog.settings.notices.popup.visible and dialog.settings.notices.popup.size.y >= 100 and dialog.settings.notices.popup.size.y < dialog.get_viewport_rect().size.y - 24, "Notice text opens in a visible popup with usable height")
	dialog.settings.notices.popup.hide()
	tabs.current_tab = 1
	var editor: RefCounted = dialog.settings.controls
	editor.begin("move_up")
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_CTRL
	event.ctrl_pressed = true
	_check(not menu.preferences.bindings.from_event(event).is_empty(), "Standalone Ctrl is a bindable key")
	event.physical_keycode = KEY_I
	_check(menu.preferences.bindings.from_event(event).is_empty(), "Ctrl plus another key is rejected as a chord")
	event.ctrl_pressed = false
	event.physical_keycode = KEY_D
	menu.call("_input", event)
	_check(not editor.pending.is_empty(), "Conflicting assignment is rejected")
	event.physical_keycode = KEY_I
	menu.call("_input", event)
	_check(editor.pending.is_empty() and InputMap.action_has_event("move_up", event), "Binding capture changes actual movement input")
	var loaded := PREFS.new()
	loaded.load_settings()
	_check(loaded.bindings.values.move_up.code == KEY_I, "Binding survives config reload")
	editor.begin("reload")
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	menu.call("_input", event)
	_check(editor.pending.is_empty() and menu.modal == dialog, "Escape cancels capture without closing settings")
	var mouse := InputEventMouseButton.new()
	mouse.pressed = true
	mouse.button_index = MOUSE_BUTTON_RIGHT
	editor.begin("mutation_tree")
	menu.call("_input", mouse)
	_check(InputMap.action_has_event("mutation_tree", mouse), "Mouse button rebinding applies to mutation action")
	dialog.call("_language_changed", 1)
	await process_frame
	_check(dialog.find_children("*", "PopupPanel", true, false).size() == 1, "Language rebuild frees the previous notice popup")
	_check(dialog.settings.tabs.current_tab == 1 and dialog.settings.tabs.get_tab_title(1) == "Controls", "Language change preserves active tab")
	dialog.call("_defaults")
	_check(menu.preferences.bindings.values.move_up.code == KEY_W and menu.preferences.values.bullet_impact_smoke and menu.preferences.values.sunlight and menu.preferences.values.walk_speed_multiplier == 1.0 and menu.preferences.values.walk_animation_multiplier == 1.0, "Reset restores controls, sunlight and both walk multipliers")
	menu.close_dialog()
	menu.activate("about")
	await process_frame
	var found := false
	for label: Label in menu.modal.find_children("*", "Label", true, false):
		if label.text == "VECTRION":
			found = true
			_check(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "VECTRION heading is centred")
	_check(found, "Company heading exists")
	frontend.free()
	await process_frame
	if had:
		var file := FileAccess.open(PREFS.FILE, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else:
		DirAccess.remove_absolute(PREFS.FILE)
	InputMap.load_from_project_settings()
	await create_timer(0.2).timeout
	print("Settings tabs tests: %d failures" % failures)
	quit(failures)

const SHADOWS_OFF_DISTANCE := 0.5


func _sunlight_checks(tabs: TabContainer, dialog: Control) -> void:
	_smoke_checks(tabs)
	var sunlight := tabs.get_child(2).find_child("Sunlight", true, false) as CheckButton
	_check(sunlight != null, "Sunlight toggle belongs to Video")
	if sunlight == null:
		return
	_check(sunlight.button_pressed and sunlight.text == "Солнце" and not sunlight.tooltip_text.is_empty(), "Sunlight defaults on and has a translated explanation")
	sunlight.set_pressed(false)
	var saved := PREFS.new()
	saved.load_settings()
	_check(not saved.values.sunlight and saved.values.lighting, "Sunlight off persists independently of local lighting")
	var config := ConfigFile.new()
	_check(config.load(PREFS.FILE) == OK, "Settings file is readable")
	config.erase_section_key("interface_v1", "sunlight")
	config.set_value("interface_v1", "lighting", false)
	_check(config.save(PREFS.FILE) == OK, "Legacy settings fixture is saved")
	var legacy := PREFS.new()
	legacy.load_settings()
	_check(legacy.values.sunlight and not legacy.values.lighting, "Legacy settings default sunlight on without enabling old lighting-off preference")
	config.set_value("interface_v1", "sunlight", "false")
	config.save(PREFS.FILE)
	var malformed := PREFS.new()
	malformed.load_settings()
	_check(malformed.values.sunlight, "Malformed sunlight value retains typed default")
	_check(dialog.view.preferences.save_settings() == OK, "Live settings replace the fixture")
	sunlight.set_pressed(true)
	_check(dialog.view.preferences.values.sunlight, "Sunlight can be re-enabled")


func _shadow_checks(tabs: TabContainer, dialog: Control) -> void:
	var shadows := tabs.get_child(2).find_child("Shadows", true, false) as CheckButton
	var quality := tabs.get_child(2).find_child("ShadowQuality", true, false) as HSlider
	_check(shadows != null and shadows.button_pressed, "Shadows toggle belongs to Video and defaults on")
	_check(quality != null and quality.value == 1.0 and quality.max_value == 3.0 and quality.step == 1.0, "Shadow quality slider has 4 levels and defaults to Medium")
	quality.value = 0.0
	await create_timer(0.6).timeout
	_check(PREFS.new().values.shadow_quality == 1, "Fresh preferences keep the default quality")
	var shadow_prefs := PREFS.new()
	shadow_prefs.load_settings()
	_check(int(shadow_prefs.values.shadow_quality) == 0, "Shadow quality survives settings reload")
	_check(dialog.view.text("shadowQuality0") == "Низкое", "Shadow quality level is named")
	var stage := Node3D.new()
	var sun := DirectionalLight3D.new()
	sun.name = "GlobalOverheadLight"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	stage.add_child(sun)
	root.add_child(stage)
	var previous_scene := current_scene
	current_scene = stage
	shadow_prefs.values.shadows = false
	shadow_prefs.values.shadow_quality = 0
	shadow_prefs.apply_to_game(self)
	_check(sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, SHADOWS_OFF_DISTANCE), "Off shrinks the sun's range without touching shader-variant switches")
	shadow_prefs.values.shadows = true
	shadow_prefs.values.shadow_quality = 2
	shadow_prefs.apply_to_game(self)
	_check(sun.shadow_enabled and sun.directional_shadow_max_distance == 80.0 and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "High quality restores the authored shadow setup")
	shadow_prefs.values.shadow_quality = 0
	shadow_prefs.apply_to_game(self)
	_check(sun.directional_shadow_max_distance == 32.0 and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "Low quality shortens range and keeps the split mode")
	shadow_prefs.values.shadow_quality = 2
	shadow_prefs.apply_to_game(self)
	var mesh_lod := tabs.get_child(2).find_child("MeshLod", true, false) as CheckButton
	_check(mesh_lod != null and mesh_lod.button_pressed and PREFS.new().values.mesh_lod, "LOD toggle belongs to Video and defaults on")
	shadow_prefs.values.mesh_lod = false
	shadow_prefs.apply_to_game(self)
	_check(root.mesh_lod_threshold == 0.0, "LOD off disables automatic mesh LOD")
	shadow_prefs.values.mesh_lod = true
	shadow_prefs.apply_to_game(self)
	_check(root.mesh_lod_threshold == 1.0, "LOD on restores the engine default")
	current_scene = previous_scene
	stage.queue_free()
	quality.value = 2.0


func _general_checks(tabs: TabContainer) -> void:
	_quality_checks(tabs)
	_check_presentation_options(tabs)
	_enemy_modes_checks(tabs)
	_dodge_checks(tabs)
	_walk_checks(tabs)


func _walk_checks(tabs: TabContainer) -> void:
	for key in ["walk_speed_multiplier", "walk_animation_multiplier"]:
		var slider := tabs.get_child(0).find_child(key.to_pascal_case(), true, false) as HSlider
		_check(slider != null, "Walk tuning slider belongs to General: " + key)
		if slider == null:
			continue
		var label := tabs.get_child(0).find_child(slider.name + "Value", true, false) as Label
		_check(slider.value == 1.0 and slider.min_value == 0.5 and slider.step == 0.05, "Walk tuning defaults and steps are usable")
		_check(slider.max_value == (1.5 if key == "walk_speed_multiplier" else 2.0), "Walk tuning maximum matches the runtime range")
		_check(label != null and label.text == "1.00×", "Multiplier value is displayed beside the slider")
		var before := PREFS.new()
		before.load_settings()
		slider.drag_started.emit()
		slider.value = 1.25
		var during := PREFS.new()
		during.load_settings()
		_check(during.values[key] == before.values[key], "Dragging walk tuning avoids settings writes")
		_check(label.text == "1.25×", "Displayed multiplier follows live changes")
		slider.drag_ended.emit(true)
		var saved := PREFS.new()
		saved.load_settings()
		_check(saved.values[key] == 1.25, "Walk tuning survives config reload")
		slider.value = 1.0


func _dodge_checks(tabs: TabContainer) -> void:
	var dodge := tabs.get_child(0).find_child("DodgeAnimation", true, false) as OptionButton
	_check(dodge != null and dodge.item_count == 2 and dodge.selected == 0, "Dodge animation (roll / strafe jump) sits in General and defaults to the roll")
	dodge.item_selected.emit(1)
	var dodge_prefs := PREFS.new()
	dodge_prefs.load_settings()
	_check(dodge_prefs.values.dodge_animation == 1, "Dodge animation choice survives settings reload")
	dodge.item_selected.emit(0)


func _quality_checks(tabs: TabContainer) -> void:
	var quality := tabs.get_child(2).find_child("EffectsQuality", true, false) as OptionButton
	_check(quality != null and quality.item_count == 3 and quality.selected == 2, "Effects quality belongs to Video: low, medium, high, default high")
	quality.select(0)
	quality.item_selected.emit(0)
	var quality_prefs := PREFS.new()
	quality_prefs.load_settings()
	_check(quality_prefs.values.effects_quality == 0 and EFFECTS_QUALITY.level == 0, "Effects quality survives reload and reaches the effects")
	quality.select(2)
	quality.item_selected.emit(2)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _check_notice_badge(dialog: Control, tabs: TabContainer) -> void:
	var notices: RefCounted = dialog.settings.notices
	var badge: Button = notices.badge
	_check(badge.is_inside_tree() and dialog.is_ancestor_of(badge) and badge.text == "!", "One shared ! badge serves every tab")
	for page_index in 4:
		_check(not tabs.get_child(page_index).is_ancestor_of(badge), "Notice badge stays outside scrolling tab contents")
	tabs.current_tab = 0
	_check(badge.visible, "General shows its own notice")
	tabs.current_tab = 3
	_check(not badge.visible, "Audio without a notice hides the badge")
	tabs.current_tab = 1
	_check(badge.visible and badge.tooltip_text == notices.messages[1], "Badge follows the active tab's notice")
	tabs.current_tab = 0
	var page_margin := tabs.get_child(0).get_child(0) as MarginContainer
	_check(page_margin.get_theme_constant("margin_top") >= 24, "Tab contents keep a clear gap below the tabs")
	var page_style := tabs.get_theme_stylebox("panel") as StyleBoxFlat
	_check(page_style != null and page_style.bg_color.a == 0.0, "Tab pages share the dialog background")


# A dragged slider changes the live value at once but writes the file only when released.
func _slider_checks(tabs: TabContainer) -> void:
	var sliders := tabs.get_child(3).find_children("*", "HSlider", true, false)
	_check(not sliders.is_empty(), "Audio page has volume sliders")
	if sliders.is_empty():
		return
	var slider := tabs.get_child(3).find_child("MusicVolume", true, false) as HSlider
	_check(slider != null, "Gameplay music slider is found by its setting key")
	if slider == null:
		return
	var before := PREFS.new()
	before.load_settings()
	slider.drag_started.emit()
	slider.value = 0.15
	var during := PREFS.new()
	during.load_settings()
	_check(is_equal_approx(during.values.music_volume, before.values.music_volume), "Dragging a slider does not write the settings file")
	slider.drag_ended.emit(true)
	var after := PREFS.new()
	after.load_settings()
	_check(is_equal_approx(after.values.music_volume, 0.15), "Releasing the slider saves the new value once")


func _smoke_checks(tabs: TabContainer) -> void:
	var smoke := tabs.get_child(2).find_child("BulletImpactSmoke", true, false) as CheckButton
	_check(smoke != null and smoke.button_pressed and smoke.text == "Дым от попаданий пуль", "Translated smoke toggle defaults on in Video")
	if smoke == null:
		return
	_check(not smoke.tooltip_text.is_empty(), "Smoke toggle explains its effect")
	smoke.set_pressed(false)
	var saved := PREFS.new()
	saved.load_settings()
	_check(not saved.values.bullet_impact_smoke and saved.values.electronic_particles, "Smoke off persists independently of electronic sparks")
	smoke.set_pressed(true)


func _check_presentation_options(tabs: TabContainer) -> void:
	_check(tabs.get_child(0).find_child("TextScale", true, false) != null, "Text scale belongs to General")
	_check(tabs.get_child(2).find_child("TextScale", true, false) == null, "Text scale is absent from Video")
	_check(tabs.find_child("SkillEffects", true, false) == null, "Obsolete sprite choice is removed")
	var only := tabs.get_child(2).find_child("GameLightsOnly", true, false) as CheckButton
	_check(only != null and not only.button_pressed, "Game-only lighting belongs to Video and preserves the legacy default")
	var prefs := PREFS.new()
	prefs.load_settings()
	var previous: bool = prefs.values.game_lights_only
	prefs.values.game_lights_only = true
	prefs.save_settings()
	var reloaded := PREFS.new()
	reloaded.load_settings()
	_check(reloaded.values.game_lights_only, "Game-only lighting survives settings reload")
	prefs.values.game_lights_only = previous
	prefs.save_settings()
func _enemy_modes_checks(tabs: TabContainer) -> void:
	for entry in [["EnemiesIgnorePlayer", "enemies_ignore_player"], ["EnemiesNoDamage", "enemies_no_damage"]]:
		var toggle := tabs.get_child(0).find_child(entry[0], true, false) as CheckButton
		_check(toggle != null, "Enemy mode belongs to General")
		if toggle == null:
			continue
		_check(not toggle.button_pressed and not toggle.tooltip_text.is_empty(), "Enemy mode defaults off with explanation")
		toggle.set_pressed(true)
		var saved := PREFS.new()
		saved.load_settings()
		_check(bool(saved.values[entry[1]]), "Enemy mode survives settings reload")
		toggle.set_pressed(false)
	var defaults := PREFS.new()
	defaults.values.enemies_ignore_player = true
	defaults.values.enemies_no_damage = true
	defaults.reset()
	_check(not defaults.values.enemies_ignore_player and not defaults.values.enemies_no_damage, "Reset restores ordinary enemy rules")
	var before := FileAccess.get_file_as_bytes(PREFS.FILE)
	var malformed := ConfigFile.new()
	malformed.set_value("interface_v1", "enemies_ignore_player", "yes")
	malformed.set_value("interface_v1", "enemies_no_damage", 1)
	malformed.save(PREFS.FILE)
	var legacy := PREFS.new()
	legacy.load_settings()
	_check(not legacy.values.enemies_ignore_player and not legacy.values.enemies_no_damage, "Malformed or missing preference flags preserve ordinary gameplay")
	FileAccess.open(PREFS.FILE, FileAccess.WRITE).store_buffer(before)
	var mission := load("res://game/bootstrap/app/main.gd").new() as Node3D
	var target := Node3D.new()
	mission.set("player", target)
	mission.call("set_enemy_gameplay_modes", true, false)
	_check(target.get_meta("enemy_gameplay_modes_v1").ignore_player, "Mission settings command injects policy into its player")
	target.free()
	mission.free()
