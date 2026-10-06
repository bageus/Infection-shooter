extends PanelContainer

# Hover card for mutation-tree circles: replaces the plain engine tooltip with a
# compact panel in the shared menu style, docked beside the hovered circle.

const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
const ACCENT := Color("a52d30")
const GOOD := Color(0.42, 0.86, 0.25)
const BAD := Color("d0585b")
const WIDTH := 300.0
const GAP := 14.0
# Wrapped labels need a fixed width to report their height before layout.
const TEXT_WIDTH := WIDTH - 30.0

var anchor_id := ""
var _title: Label
var _kind: Label
var _body: Label
var _rows: VBoxContainer
var _status: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = WIDTH
	z_index = 10
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("151a1cf7")
	frame.border_color = Color("646760")
	frame.set_border_width_all(1)
	frame.content_margin_left = 16
	frame.content_margin_right = 14
	frame.content_margin_top = 12
	frame.content_margin_bottom = 12
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 10
	add_theme_stylebox_override("panel", frame)
	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)
	_kind = STYLE.label("", 10)
	_kind.add_theme_color_override("font_color", STYLE.MUTED)
	layout.add_child(_kind)
	_title = STYLE.label("", 20, true)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = TEXT_WIDTH
	_title.add_theme_color_override("font_color", STYLE.INK)
	layout.add_child(_title)
	layout.add_child(_divider())
	_body = STYLE.label("", 14)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = TEXT_WIDTH
	_body.add_theme_color_override("font_color", STYLE.INK)
	layout.add_child(_body)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 2)
	layout.add_child(_rows)
	_status = STYLE.label("", 11)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = TEXT_WIDTH
	layout.add_child(_status)
	hide()


# info: {title, kind, body, rows: [[caption, value, met]], status, status_color}
func present(id: String, info: Dictionary, target: Rect2, bounds: Rect2) -> void:
	anchor_id = id
	_kind.text = str(info.get("kind", "")).to_upper()
	_title.text = str(info.get("title", "")).to_upper()
	_body.text = str(info.get("body", ""))
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var rows: Array = info.get("rows", [])
	_rows.visible = not rows.is_empty()
	for row in rows:
		_rows.add_child(_requirement(str(row[0]), str(row[1]), bool(row[2])))
	_status.text = str(info.get("status", "")).to_upper()
	_status.visible = not _status.text.is_empty()
	_status.add_theme_color_override("font_color", info.get("status_color", STYLE.MUTED))
	size = Vector2(WIDTH, 0)
	show()
	reset_size()
	_place(target, bounds)


func _draw() -> void:
	# Same red marker the menus use for the focused entry.
	draw_rect(Rect2(0, 0, 3, size.y), ACCENT)


func dismiss(id: String = "") -> void:
	if id.is_empty() or id == anchor_id:
		anchor_id = ""
		hide()


func _place(target: Rect2, bounds: Rect2) -> void:
	var card := get_combined_minimum_size()
	size = card
	var x := target.end.x + GAP
	if x + card.x > bounds.end.x:
		x = target.position.x - GAP - card.x
	var y := target.get_center().y - card.y * 0.5
	position = Vector2(
		clampf(x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - card.x)),
		clampf(y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - card.y)))


func _requirement(caption: String, value: String, met: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := STYLE.label("✓" if met else "✕", 12)
	mark.custom_minimum_size.x = 16
	mark.add_theme_color_override("font_color", GOOD if met else BAD)
	row.add_child(mark)
	var label := STYLE.label(caption, 12)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", STYLE.MUTED)
	row.add_child(label)
	var amount := STYLE.label(value, 12)
	amount.add_theme_color_override("font_color", STYLE.INK if met else BAD)
	row.add_child(amount)
	return row


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0.64, 0.64, 0.61, 0.32)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
