extends Node
## One bootstrap-owned platform adapter for the application's root window.
const CATALOG := preload("res://game/bootstrap/app/menu/display_catalog.gd")
var _window: Window
var _resolution := ""
var _mode := -1
var _wanted := Vector2i.ZERO


static func screen_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(1920, 1080)
	var size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	return size if size.x > 0 and size.y > 0 else Vector2i(1280, 720)


static func apply_to(window: Window, values: Dictionary, user_action: bool = false) -> void:
	var adapter := window.get_node_or_null("DisplaySettings")
	if adapter == null:
		adapter = load("res://game/bootstrap/app/menu/display_settings.gd").new()
		adapter.name = "DisplaySettings"
		adapter.process_mode = Node.PROCESS_MODE_ALWAYS
		window.add_child(adapter)
		adapter.set("_window", window)
		window.size_changed.connect(Callable(adapter, "_update_render_scale"))
	adapter.call("configure", values, user_action)


func configure(values: Dictionary, user_action: bool) -> void:
	var mode := clampi(int(values.window_mode), 0, 1)
	var resolution := CATALOG.resolve(str(values.resolution), screen_size(), mode == 1)
	values.resolution = resolution
	if _mode == mode and _resolution == resolution:
		_update_render_scale()
		return
	_mode = mode
	_resolution = resolution
	_wanted = CATALOG.parse(resolution)
	if DisplayServer.get_name() != "headless":
		_apply_native(user_action)
	_update_render_scale.call_deferred()


func _apply_native(user_action: bool) -> void:
	# Browsers own canvas/window size and require a gesture for fullscreen.
	if OS.has_feature("web"):
		if user_action:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if _mode == 1 else DisplayServer.WINDOW_MODE_WINDOWED)
		return
	var native_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if _mode == 1 else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != native_mode:
		DisplayServer.window_set_mode(native_mode)
	if _mode == 0:
		_place_window.call_deferred()


func _place_window() -> void:
	await get_tree().process_frame
	if _mode != 0 or DisplayServer.get_name() == "headless":
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var wanted := _wanted if _wanted != Vector2i.ZERO else screen_size()
	var rect := CATALOG.fit_window(wanted, usable)
	DisplayServer.window_set_size(rect.size)
	DisplayServer.window_set_position(rect.position)


func _update_render_scale() -> void:
	# Read the settled viewport; never scale menu/font pixels or camera input.
	var scale := CATALOG.render_scale(_wanted, _window.size) if _mode == 1 or OS.has_feature("web") else 1.0
	_window.scaling_3d_scale = scale
