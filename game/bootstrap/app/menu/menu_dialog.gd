extends Control

const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
const MARK := preload("res://assets/interface/branding/vectrion_mark.svg")
var view
var kind := ""
var layout: VBoxContainer
var panel: PanelContainer
var _focus_return: Control


func setup(owner_view: Control, dialog_kind: String) -> void:
	view = owner_view
	kind = dialog_kind
	_focus_return = get_viewport().gui_get_focus_owner()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color("080b0fd9")
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("151a1cf5")
	style.border_color = Color("646760")
	style.set_border_width_all(1)
	style.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -290
	panel.offset_right = 290
	panel.offset_top = -310
	panel.offset_bottom = 310
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	layout = VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	scroll.add_child(layout)
	_build()
	call_deferred("_focus_first")


func _build() -> void:
	match kind:
		"settings":
			_settings()
		"about":
			var logo := TextureRect.new()
			logo.texture = MARK
			logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			logo.custom_minimum_size = Vector2(70, 70)
			layout.add_child(logo)
			_heading("VECTRION", false)
			_copy("corporation")
			_copy("corpNote")
			_copy("aboutNote")
			_button("back", view.close_dialog)
		"briefing":
			_heading("patient")
			for index in range(1, 4):
				_copy("brief" + str(index), str(index) + ". ")
			_copy("warning")
			_button("deploy", view.dispatch.bind("start"))
			_button("back", view.close_dialog)
		_:
			var prefix: String = {"quit": "exit", "main": "leave", "restart": "retry"}[kind]
			_heading(prefix + "Title")
			_copy(prefix + "Copy")
			_button("confirm", view.dispatch.bind(kind))
			_button("cancel", view.close_dialog)


func _heading(key: String, translated: bool = true) -> void:
	var title := STYLE.label((view.text(key) if translated else key).to_upper(), 30, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(title)


func _copy(key: String, prefix: String = "") -> void:
	var label := STYLE.label(prefix + view.text(key), roundi(14 * view.preferences.values.text_scale))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", STYLE.MUTED)
	layout.add_child(label)


func _button(key: String, callback: Callable) -> Button:
	var result := STYLE.button(view.text(key), callback)
	layout.add_child(result)
	return result


func _settings() -> void:
	_heading("settings")
	_slider("volume", "volume", 0, 1, 0.05)
	_slider("brightness", "brightness", 0.8, 1.4, 0.05)
	var sound := CheckButton.new()
	sound.text = view.text("sound")
	sound.button_pressed = view.preferences.values.sound
	sound.toggled.connect(func(value: bool) -> void: _change("sound", value))
	layout.add_child(sound)
	var language := OptionButton.new()
	language.add_item("Русский")
	language.add_item("English")
	language.selected = 1 if view.preferences.values.language == "en" else 0
	language.item_selected.connect(_language_changed)
	_row("language", language)
	var scale := OptionButton.new()
	for percent in [100, 115, 130]:
		scale.add_item(str(percent) + "%")
	scale.selected = [1.0, 1.15, 1.3].find(view.preferences.values.text_scale)
	scale.item_selected.connect(_scale_changed)
	_row("scale", scale)
	_copy("savedSettings")
	_button("fullscreen", _fullscreen)
	_button("defaults", _defaults)
	_button("done", view.close_dialog)


func _slider(label_key: String, setting_key: String, minimum: float, maximum: float, step_size: float) -> void:
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 160
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.value = view.preferences.values[setting_key]
	slider.value_changed.connect(func(value: float) -> void: _change(setting_key, value))
	_row(label_key, slider)


func _row(key: String, widget: Control) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 40
	var label := STYLE.label(view.text(key), 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(widget)
	layout.add_child(row)


func _change(key: String, value: Variant) -> void:
	view.preferences.values[key] = value
	if view.preferences.save_settings() != OK:
		_copy("storeUnavailable")
	view.preferences.apply_to_game(view.get_tree())
	view.refresh()


func _language_changed(index: int) -> void:
	_change("language", "en" if index == 1 else "ru")
	_rebuild()


func _scale_changed(index: int) -> void:
	_change("text_scale", [1.0, 1.15, 1.3][index])
	_rebuild()


func _defaults() -> void:
	view.preferences.reset()
	if view.preferences.save_settings() != OK:
		_copy("storeUnavailable")
	view.preferences.apply_to_game(view.get_tree())
	view.refresh()
	_rebuild()


func _rebuild() -> void:
	for child in layout.get_children():
		layout.remove_child(child)
		child.queue_free()
	_build()
	call_deferred("_focus_first")


func _fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _focus_first() -> void:
	if not is_inside_tree():
		return
	var controls := _controls(layout)
	if not controls.is_empty():
		controls[0].grab_focus()


func _controls(parent: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in parent.get_children():
		if child is Control and child.focus_mode == Control.FOCUS_ALL:
			result.append(child)
		result.append_array(_controls(child))
	return result


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var controls := _controls(layout)
	var focused := get_viewport().gui_get_focus_owner()
	if event.keycode == KEY_TAB or (event.keycode in [KEY_UP, KEY_DOWN] and focused is Button and not focused is OptionButton):
		var reverse: bool = event.shift_pressed if event.keycode == KEY_TAB else event.keycode == KEY_UP
		var index := controls.find(focused)
		controls[posmod(index + (-1 if reverse else 1), controls.size())].grab_focus()
		get_viewport().set_input_as_handled()
