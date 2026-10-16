extends SceneTree
const CATALOG := preload("res://game/bootstrap/app/menu/display_catalog.gd")
const DISPLAY := preload("res://game/bootstrap/app/menu/display_settings.gd")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var had := FileAccess.file_exists(PREFS.FILE)
	var saved := FileAccess.get_file_as_bytes(PREFS.FILE) if had else PackedByteArray()
	_catalog()
	_preferences()
	if DisplayServer.get_name() == "headless":
		await _adapter()
	else:
		await _native_window()
	await _ui()
	if had:
		var file := FileAccess.open(PREFS.FILE, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else:
		DirAccess.remove_absolute(PREFS.FILE)
	await create_timer(0.2).timeout
	print("Display settings tests: %d failures" % failures)
	quit(1 if failures else 0)


func _catalog() -> void:
	for native in [Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1600),
			Vector2i(3440, 1440), Vector2i(3840, 2160), Vector2i(5120, 1440), Vector2i(1024, 600)]:
		for fullscreen in [false, true]:
			var choices := CATALOG.available(native, fullscreen)
			_check(choices.has(native), "Native resolution is always available")
			var seen: Array[Vector2i] = []
			for size in choices:
				_check(size.x <= native.x and size.y <= native.y and not seen.has(size), "List excludes oversize and duplicate sizes")
				if fullscreen:
					_check(absf(float(size.x) / size.y - float(native.x) / native.y) <= 0.02, "Fullscreen preserves monitor aspect")
				seen.append(size)
	var fullhd := CATALOG.available(Vector2i(1920, 1080), true)
	_check(fullhd.has(Vector2i(1280, 720)) and fullhd.has(Vector2i(1600, 900)), "720p and 900p remain available on integrated GPUs")
	_check(CATALOG.resolve("3840x2160", Vector2i(1920, 1080), true) == "1920x1080", "Old 4K setting safely adapts to a smaller monitor")
	_check(CATALOG.resolve("1280x800", Vector2i(1920, 1080), true) == "1280x720", "Aspect change picks a lower affordable render budget")
	_check(CATALOG.resolve("auto", Vector2i(1366, 768), false) == "auto", "Automatic keeps its portable identity")
	_check(CATALOG.parse("bad") == Vector2i.ZERO and CATALOG.parse("0x0") == Vector2i.ZERO, "Invalid dimensions are rejected")
	var work := Rect2i(-1920, 40, 1920, 1000)
	var fitted := CATALOG.fit_window(Vector2i(3840, 2160), work)
	_check(work.encloses(fitted) and fitted.size.x < work.size.x and fitted.size.y < work.size.y, "Window fits a monitor with a negative desktop origin and decorations")
	_check(absf(CATALOG.render_scale(Vector2i(1280, 720), Vector2i(1920, 1080)) - 2.0 / 3.0) < 0.00001, "720p reduces Full HD 3D rendering to two thirds per axis")
	_check(CATALOG.render_scale(Vector2i(3840, 2160), Vector2i(1920, 1080)) == 1.0, "Resolution never enables expensive supersampling")


func _preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("interface_v1", "language", "ru")
	_check(config.save(PREFS.FILE) == OK, "Legacy fixture saves")
	var legacy := PREFS.new()
	legacy.load_settings()
	_check(legacy.values.window_mode == 0 and legacy.values.resolution == "1280x720", "Old configs preserve windowed 720p")
	config.set_value("interface_v1", "window_mode", "fullscreen")
	config.set_value("interface_v1", "resolution", 1080)
	config.save(PREFS.FILE)
	var typed := PREFS.new()
	typed.load_settings()
	_check(typed.values.window_mode == 0 and typed.values.resolution == "1280x720", "Wrong config types retain defaults")
	config.set_value("interface_v1", "window_mode", 999)
	config.set_value("interface_v1", "resolution", "0x0")
	config.save(PREFS.FILE)
	var bounded := PREFS.new()
	bounded.load_settings()
	_check(bounded.values.window_mode == 1 and bounded.values.resolution == "1280x720", "Loaded values are bounded and dimensions validated")
	bounded.values.resolution = "1600x900"
	bounded.save_settings()
	var loaded := PREFS.new()
	loaded.load_settings()
	_check(loaded.values.window_mode == 1 and loaded.values.resolution == "1600x900", "Display choices survive config round-trip")
	loaded.reset()
	_check(loaded.values.window_mode == 0 and loaded.values.resolution == "1280x720", "Reset restores safe original display defaults")
	loaded.save_settings()


func _adapter() -> void:
	var window := Window.new()
	root.add_child(window)
	window.size = Vector2i(1920, 1080)
	var canvas_size := window.content_scale_size
	var canvas_mode := window.content_scale_mode
	var values := {"window_mode": 1, "resolution": "1280x720"}
	DISPLAY.apply_to(window, values)
	await process_frame
	var adapter := window.get_node("DisplaySettings")
	_check(absf(window.scaling_3d_scale - 2.0 / 3.0) < 0.00001, "Adapter applies actual 3D scale")
	_check(window.content_scale_size == canvas_size and window.content_scale_mode == canvas_mode, "Display choice leaves UI canvas and input coordinate scale unchanged")
	for i in 10:
		DISPLAY.apply_to(window, values)
	_check(window.get_node("DisplaySettings") == adapter and window.get_child_count() == 1, "Repeated volume/settings applies reuse one adapter")
	window.size = Vector2i(2560, 1440)
	await process_frame
	_check(absf(window.scaling_3d_scale - 0.5) < 0.00001, "Asynchronous resize recomputes 3D scale from the settled viewport")
	values.window_mode = 0
	DISPLAY.apply_to(window, values)
	await process_frame
	_check(window.scaling_3d_scale == 1.0, "Windowed mode removes fullscreen downscale")
	values.window_mode = 1
	values.resolution = "auto"
	DISPLAY.apply_to(window, values)
	await process_frame
	_check(window.scaling_3d_scale == 1.0, "Auto renders at native viewport size")
	window.queue_free()
	await process_frame


func _native_window() -> void:
	var values := {"window_mode": 0, "resolution": "1280x720"}
	DISPLAY.apply_to(root, values, true)
	await _settle_native(DisplayServer.WINDOW_MODE_WINDOWED, CATALOG.fit_window(Vector2i(1280, 720), DisplayServer.screen_get_usable_rect()).size)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Native display starts in windowed mode")
	var work := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var rect := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	_check(work.encloses(rect), "Native window fits the usable desktop")
	var position := DisplayServer.window_get_position()
	var size := DisplayServer.window_get_size()
	for i in 5:
		DISPLAY.apply_to(root, values)
	await process_frame
	_check(DisplayServer.window_get_position() == position and DisplayServer.window_get_size() == size, "Repeated preference apply preserves native position and size")
	values.window_mode = 1
	DISPLAY.apply_to(root, values, true)
	await _settle_native(DisplayServer.WINDOW_MODE_FULLSCREEN, DISPLAY.screen_size())
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Native display enters fullscreen")
	_check(root.size == DISPLAY.screen_size(), "Fullscreen uses the actual monitor size: root=%s native=%s screen=%s" % [root.size, DisplayServer.window_get_size(), DISPLAY.screen_size()])
	_check(absf(root.scaling_3d_scale - CATALOG.render_scale(Vector2i(1280, 720), root.size)) < 0.00001, "Native fullscreen retains the chosen 720p 3D budget")
	values.window_mode = 0
	values.resolution = "1600x900"
	DISPLAY.apply_to(root, values, true)
	await _settle_native(DisplayServer.WINDOW_MODE_WINDOWED, CATALOG.fit_window(Vector2i(1600, 900), work).size)
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and root.scaling_3d_scale == 1.0, "Returning to windowed restores normal rendering")
	_check(root.size == CATALOG.fit_window(Vector2i(1600, 900), work).size, "Returning from fullscreen applies the saved window dimensions: root=%s native=%s expected=%s" % [root.size, DisplayServer.window_get_size(), CATALOG.fit_window(Vector2i(1600, 900), work).size])


# Require both OS and scene viewport to agree, then observe two stable frames.
func _settle_native(mode: int, size: Vector2i) -> void:
	var deadline := Time.get_ticks_msec() + 2000
	var stable := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if DisplayServer.window_get_mode() == mode and root.size == size and DisplayServer.window_get_size() == size:
			stable += 1
			if stable >= 2:
				return
		else:
			stable = 0


func _ui() -> void:
	var frontend := FRONT.instantiate()
	root.add_child(frontend)
	current_scene = frontend
	await process_frame
	var menu: Control = frontend.get_node("Menu")
	menu.preferences.reset()
	menu.refresh()
	menu.activate("settings")
	await process_frame
	var dialog: Control = menu.modal
	var page: Node = dialog.settings.tabs.get_child(2)
	var mode := page.find_child("WindowMode", true, false) as OptionButton
	var resolution := page.find_child("Resolution", true, false) as OptionButton
	_check(mode != null and resolution != null, "Both display controls belong to Video")
	if mode != null and resolution != null:
		_check(mode.get_item_text(0) == "В окне" and mode.get_item_text(1) == "Полный экран", "Window modes have clear Russian names")
		_check(not resolution.tooltip_text.is_empty(), "Resolution explains fullscreen and small-window behavior")
		var index := _find_resolution(resolution, "1600x900")
		_check(index >= 0 and _find_resolution(resolution, "1280x720") >= 0, "Menu includes integrated-GPU sizes")
		if index >= 0:
			resolution.select(index)
			resolution.item_selected.emit(index)
		mode.item_selected.emit(1)
		await process_frame
		var saved := PREFS.new()
		saved.load_settings()
		_check(saved.values.window_mode == 1 and saved.values.resolution == "1600x900", "Real controls apply and persist both display choices")
		dialog.call("_language_changed", 1)
		await process_frame
		var english := dialog.settings.tabs.get_child(2).find_child("WindowMode", true, false) as OptionButton
		_check(english != null and english.get_item_text(0) == "Windowed" and english.selected == 1, "Language rebuild keeps selected display mode")
		dialog.call("_defaults")
		_check(menu.preferences.values.window_mode == 0 and menu.preferences.values.resolution == "1280x720", "Menu reset restores display defaults")
	frontend.queue_free()
	await process_frame


func _find_resolution(option: OptionButton, value: String) -> int:
	for i in option.item_count:
		if option.get_item_metadata(i) == value:
			return i
	return -1
