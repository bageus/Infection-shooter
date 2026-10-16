extends RefCounted
const DISPLAY := preload("res://game/bootstrap/app/menu/display_settings.gd")
const CATALOG := preload("res://game/bootstrap/app/menu/display_catalog.gd")


static func build(dialog: Control) -> void:
	var values: Dictionary = dialog.view.preferences.values
	var mode := OptionButton.new()
	mode.name = "WindowMode"
	mode.add_item(dialog.view.text("displayWindowed"))
	mode.add_item(dialog.view.text("displayFullscreen"))
	mode.selected = int(values.window_mode)
	mode.item_selected.connect(func(index: int) -> void:
		dialog.call("_change", "window_mode", index)
		dialog.call("_rebuild"))
	dialog.call("_row", "displayMode", mode)
	var resolution := OptionButton.new()
	resolution.name = "Resolution"
	resolution.tooltip_text = dialog.view.text("resolutionHint")
	resolution.add_item(dialog.view.text("resolutionAuto"))
	resolution.set_item_metadata(0, "auto")
	var native := DISPLAY.screen_size()
	var selected := CATALOG.resolve(str(values.resolution), native, int(values.window_mode) == 1)
	for size in CATALOG.available(native, int(values.window_mode) == 1):
		var text := "%d × %d" % [size.x, size.y]
		if size == native:
			text += " (" + dialog.view.text("resolutionNative") + ")"
		resolution.add_item(text)
		var index := resolution.item_count - 1
		resolution.set_item_metadata(index, CATALOG.identifier(size))
		if CATALOG.identifier(size) == selected:
			resolution.selected = index
	resolution.item_selected.connect(func(index: int) -> void:
		dialog.call("_change", "resolution", resolution.get_item_metadata(index)))
	dialog.call("_row", "resolution", resolution)
