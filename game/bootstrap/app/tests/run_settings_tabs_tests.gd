extends SceneTree
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	_check(tabs.get_child(3).find_child("SoundToggle", true, false) != null, "Sound belongs to Audio")
	tabs.current_tab = 1
	var editor: RefCounted = dialog.settings.controls
	editor.begin("move_up")
	var event := InputEventKey.new()
	event.pressed = true
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
	print("Settings tabs tests: %d failures" % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
