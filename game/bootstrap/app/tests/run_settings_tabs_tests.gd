extends SceneTree
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
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
	var lighting := tabs.get_child(2).find_child("Lighting", true, false) as CheckButton
	_check(lighting != null and lighting.button_pressed, "Lighting belongs to Video and defaults on")
	lighting.set_pressed(false)
	var light_prefs := PREFS.new()
	light_prefs.load_settings()
	_check(not light_prefs.values.lighting, "Lighting toggle survives settings reload")
	lighting.set_pressed(true)
	_shadow_checks(tabs, dialog)
	_check(tabs.get_child(3).find_child("SoundToggle", true, false) != null, "Sound belongs to Audio")
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
	_check(menu.preferences.bindings.values.move_up.code == KEY_W, "Reset restores authored controls")
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

func _shadow_checks(tabs: TabContainer, dialog: Control) -> void:
	var shadows := tabs.get_child(2).find_child("Shadows", true, false) as CheckButton
	var quality := tabs.get_child(2).find_child("ShadowQuality", true, false) as HSlider
	_check(shadows != null and shadows.button_pressed, "Shadows toggle belongs to Video and defaults on")
	_check(quality != null and quality.value == 2.0 and quality.max_value == 3.0 and quality.step == 1.0, "Shadow quality slider has 4 levels and defaults to High")
	quality.value = 0.0
	_check(PREFS.new().values.shadow_quality == 2, "Fresh preferences keep the default quality")
	var shadow_prefs := PREFS.new()
	shadow_prefs.load_settings()
	_check(int(shadow_prefs.values.shadow_quality) == 0, "Shadow quality survives settings reload")
	_check(dialog.view.text("shadowQuality0") == "Низкое", "Shadow quality level is named")
	var stage := Node3D.new()
	var sun := DirectionalLight3D.new()
	sun.name = "GlobalOverheadLight"
	sun.shadow_enabled = true
	stage.add_child(sun)
	root.add_child(stage)
	var previous_scene := current_scene
	current_scene = stage
	shadow_prefs.values.shadows = false
	shadow_prefs.values.shadow_quality = 0
	shadow_prefs.apply_to_game(self)
	_check(not sun.shadow_enabled and sun.directional_shadow_max_distance == 32.0, "Low quality shortens range and off disables shadows")
	shadow_prefs.values.shadows = true
	shadow_prefs.values.shadow_quality = 2
	shadow_prefs.apply_to_game(self)
	_check(sun.shadow_enabled and sun.directional_shadow_max_distance == 64.0 and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "High quality restores the authored shadow setup")
	current_scene = previous_scene
	stage.queue_free()
	quality.value = 2.0


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
