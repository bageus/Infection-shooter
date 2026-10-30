extends Control
## Draws one training step: a veil with an opening over the target, a highlight frame,
## an optional arrow and a short card. It reports presses; the coordinator decides what they mean.

signal acknowledged

const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const ACCENT := Color(0.93, 0.36, 0.27, 1.0)
const VEIL_COLOR := Color(0.02, 0.03, 0.04, 1.0)
const HOLE_PADDING := 6.0
const FRAME_WIDTH := 2.0
const CARD_WIDTH := 360.0
const GAP := 16.0

var _veil := 0.0
var _rects: Array[Rect2] = []
var _arrow := false
var _advance_on_press := false
var _blocks := false
var _card: PanelContainer
var _text: Label
var _hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_text)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.66))
	_hint.text = TEXT.t("tutContinue")
	box.add_child(_hint)
	visible = false


## Shows one step. `rects` are the screen rectangles to open; an empty list veils everything.
func show_step(text: String, rects: Array[Rect2], veil: float, blocks: bool, arrow: bool, advance_on_press: bool) -> void:
	_rects = rects
	_veil = veil
	_blocks = blocks
	_arrow = arrow and not rects.is_empty()
	_advance_on_press = advance_on_press
	mouse_filter = Control.MOUSE_FILTER_STOP if blocks else Control.MOUSE_FILTER_IGNORE
	_text.text = text
	_card.visible = text != ""
	_hint.visible = advance_on_press
	visible = true
	if _card.visible:
		_card.size = Vector2(CARD_WIDTH, 0.0)
		_card.reset_size()
		_card.position = _card_position(_card.get_combined_minimum_size())
	queue_redraw()


func clear() -> void:
	visible = false
	_rects.clear()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not visible or not _advance_on_press:
		return
	var mouse_press: bool = event is InputEventMouseButton and event.pressed
	var key_press: bool = event is InputEventKey and event.pressed and not event.is_echo()
	if not mouse_press and not key_press:
		return
	if mouse_press and _blocks:
		get_viewport().set_input_as_handled()
	acknowledged.emit()


func _card_position(card_size: Vector2) -> Vector2:
	var opening := _opening()
	var x := clampf(opening.get_center().x - card_size.x * 0.5, GAP, size.x - card_size.x - GAP)
	var below := opening.end.y + GAP
	if below + card_size.y <= size.y - GAP:
		return Vector2(x, below)
	return Vector2(x, maxf(GAP, opening.position.y - GAP - card_size.y))


func _opening() -> Rect2:
	if _rects.is_empty():
		return Rect2(size * 0.5, Vector2.ZERO)
	var joined := _rects[0]
	for rect in _rects:
		joined = joined.merge(rect)
	return joined.grow(HOLE_PADDING)


func _draw() -> void:
	if _veil > 0.0:
		_draw_veil()
	for rect in _rects:
		draw_rect(rect.grow(HOLE_PADDING), ACCENT, false, FRAME_WIDTH)
	if _arrow and _card.visible:
		_draw_arrow()


func _draw_veil() -> void:
	var color := VEIL_COLOR
	color.a = _veil
	if _rects.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), color)
		return
	var hole := _opening()
	draw_rect(Rect2(0.0, 0.0, size.x, maxf(0.0, hole.position.y)), color)
	draw_rect(Rect2(0.0, hole.end.y, size.x, maxf(0.0, size.y - hole.end.y)), color)
	draw_rect(Rect2(0.0, hole.position.y, maxf(0.0, hole.position.x), hole.size.y), color)
	draw_rect(Rect2(hole.end.x, hole.position.y, maxf(0.0, size.x - hole.end.x), hole.size.y), color)


func _draw_arrow() -> void:
	var start := _card.position + Vector2(_card.size.x * 0.5, 0.0 if _card.position.y > _opening().position.y else _card.size.y)
	var finish := _opening().get_center()
	var direction := (finish - start).normalized()
	var tip := finish - direction * (_opening().size.length() * 0.5)
	var side := direction.orthogonal() * 7.0
	draw_line(start, tip - direction * 12.0, ACCENT, 3.0, true)
	draw_colored_polygon(PackedVector2Array([tip, tip - direction * 14.0 + side, tip - direction * 14.0 - side]), ACCENT)
