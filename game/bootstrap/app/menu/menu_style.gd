extends RefCounted

const BODY := preload("res://assets/interface/fonts/body.ttf")
const TITLE := preload("res://assets/interface/fonts/title.ttf")
const CURSOR := preload("res://assets/interface/ui/selection_cursor.svg")
const INK := Color("e2dfd4")
const MUTED := Color("b7b6ad")


static func make_theme(text_scale: float) -> Theme:
	var result := Theme.new()
	result.default_font = BODY
	result.default_font_size = roundi(14 * text_scale)
	result.set_color("font_color", "Label", INK)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		result.set_color(state, "Button", INK)
	result.set_color("font_disabled_color", "Button", Color("666963"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.border_color = Color(0.64, 0.64, 0.61, 0.32)
	normal.border_width_bottom = 1
	normal.content_margin_left = 25
	normal.content_margin_right = 15
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	for state in ["normal", "disabled"]:
		result.set_stylebox(state, "Button", normal)
	var highlight := StyleBoxTexture.new()
	highlight.texture = gradient(Color("74262bcc"), Color("74262b00"))
	highlight.content_margin_left = 25
	highlight.content_margin_right = 15
	highlight.content_margin_top = 10
	highlight.content_margin_bottom = 10
	for state in ["hover", "focus", "pressed"]:
		result.set_stylebox(state, "Button", highlight)
	return result


static func gradient(left: Color, right: Color) -> GradientTexture2D:
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([left, right])
	var texture := GradientTexture2D.new()
	texture.gradient = ramp
	texture.width = 512
	texture.height = 2
	texture.fill_from = Vector2(0, 0.5)
	texture.fill_to = Vector2(1, 0.5)
	return texture


static func label(text: String, font_size: int, heading: bool = false) -> Label:
	var result := Label.new()
	result.text = text
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", font_size)
	if heading:
		result.add_theme_font_override("font", TITLE)
	return result


static func button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var result := Button.new()
	result.text = text.to_upper()
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.custom_minimum_size.y = 48
	result.disabled = disabled
	result.pressed.connect(callback)
	var cursor := TextureRect.new()
	cursor.texture = CURSOR
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.position = Vector2(0, 8)
	cursor.size = Vector2(5, 32)
	cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor.visible = false
	result.add_child(cursor)
	result.focus_entered.connect(func() -> void: cursor.show())
	result.focus_exited.connect(func() -> void: cursor.hide())
	result.mouse_entered.connect(func() -> void:
		if not result.disabled:
			result.grab_focus())
	return result
