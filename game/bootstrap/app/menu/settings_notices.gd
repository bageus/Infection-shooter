extends RefCounted
## A single "!" badge in the tab bar that shows only the active tab's notice,
## independent of page scrolling.
var tabs: TabContainer
var host: Control
var messages: Dictionary = {}
var badge: Button
var detail: Label
var popup: PopupPanel
var scroll: ScrollContainer


func setup(dialog: Control, tab_view: TabContainer) -> void:
	host = dialog
	tabs = tab_view
	badge = Button.new()
	badge.name = "SettingsNotices"
	badge.text = "!"
	badge.focus_mode = Control.FOCUS_NONE
	badge.custom_minimum_size = Vector2(26, 26)
	badge.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("9a3a40") if state == "normal" else Color("b8464d")
		style.border_color = Color("e2dfd4")
		style.set_border_width_all(1)
		style.set_corner_radius_all(13)
		style.set_content_margin_all(0)
		badge.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		badge.add_theme_color_override(state, Color("f4f1e8"))
	badge.pressed.connect(func() -> void: _show(tabs.current_tab))
	# The tab bar spans the full dialog width while tabs stay centred, so the
	# badge sits on its free right edge without taking a row of its own.
	var bar := tabs.get_tab_bar()
	bar.add_child(badge)
	badge.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	badge.offset_left = -30
	badge.offset_right = -4
	badge.offset_top = -13
	badge.offset_bottom = 13
	badge.hide()
	popup = PopupPanel.new()
	dialog.add_child(popup)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	popup.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	scroll.add_child(margin)
	detail = Label.new()
	detail.name = "SettingsNoticeText"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 12)
	margin.add_child(detail)
	tabs.tab_changed.connect(func(_index: int) -> void:
		if is_instance_valid(popup):
			popup.hide()
		_refresh())


func set_notice(index: int, message: String) -> void:
	messages[index] = message
	_refresh()
	if popup.visible and tabs.current_tab == index:
		detail.text = message


func _refresh() -> void:
	if not is_instance_valid(badge):
		return
	var message := str(messages.get(tabs.current_tab, ""))
	badge.visible = not message.is_empty()
	badge.tooltip_text = message


func _show(index: int) -> void:
	tabs.current_tab = index
	var message := str(messages.get(index, ""))
	if message.is_empty():
		return
	var available := host.get_viewport_rect().size
	scroll.custom_minimum_size = Vector2(minf(444.0, available.x - 48.0), minf(180.0, available.y - 64.0))
	detail.custom_minimum_size.x = scroll.custom_minimum_size.x - 48.0
	detail.size.x = detail.custom_minimum_size.x
	detail.text = message
	popup.popup_centered.call_deferred(Vector2i(scroll.custom_minimum_size) + Vector2i(8, 8))

func dispose() -> void:
	if is_instance_valid(popup):
		popup.hide()
		popup.queue_free()
