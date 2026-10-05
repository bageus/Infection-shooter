extends RefCounted
## One persistent notice button per tab, independent of page scrolling.
var tabs: TabContainer
var host: Control
var messages: Dictionary = {}
var buttons: Array[Button] = []
var detail: Label
var popup: PopupPanel
var scroll: ScrollContainer


func setup(dialog: Control, tab_view: TabContainer) -> void:
	host = dialog
	tabs = tab_view
	var row := HBoxContainer.new()
	row.name = "SettingsNotices"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	dialog.get("layout").add_child(row)
	dialog.get("layout").move_child(row, tabs.get_index())
	for index in 4:
		var button := Button.new()
		button.text = "! " + dialog.view.text(["tabGeneral", "tabControls", "tabVideo", "tabAudio"][index])
		button.custom_minimum_size.y = 28
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_show.bind(index))
		row.add_child(button)
		buttons.append(button)
		button.hide()
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
			popup.hide())


func set_notice(index: int, message: String) -> void:
	messages[index] = message
	buttons[index].visible = not message.is_empty()
	buttons[index].tooltip_text = message
	if popup.visible and tabs.current_tab == index:
		detail.text = message


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
