extends RefCounted
## One persistent notice button per tab, independent of page scrolling.
var tabs: TabContainer
var host: Control
var messages: Dictionary = {}
var buttons: Array[Button] = []
var detail: Label
var popup: PopupPanel


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
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	popup.add_child(margin)
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
	detail.text = str(messages.get(index, ""))
	if detail.text.is_empty():
		return
	var available := host.get_viewport_rect().size
	detail.custom_minimum_size.x = minf(420.0, available.x - 64.0)
	popup.popup_centered.call_deferred(Vector2i(minf(452.0, available.x - 32.0), mini(160, int(available.y) - 32)))


func dispose() -> void:
	if is_instance_valid(popup):
		popup.hide()
		popup.queue_free()
