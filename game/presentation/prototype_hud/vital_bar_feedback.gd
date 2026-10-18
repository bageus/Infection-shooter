extends Control
## White sibling overlay for one locally injected HUD bar; its size follows only the given base scale.
const STATE := preload("res://game/presentation/prototype_hud/vital_bar_feedback_state.gd")
var state := STATE.new()
var _bar: ProgressBar
var _label: Label
var _marker: Control
var _marker_fraction := 0.0
var _dirty := true
var _base_scale := Vector2.ONE
var _blink_alpha := 1.0


func configure(bar: ProgressBar, label: Label, marker: Control = null) -> void:
	_bar = bar
	_label = label
	_marker = marker
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.get_parent().add_child(self)
	if marker != null:
		get_parent().move_child(self, marker.get_index())
	bar.resized.connect(_invalidate_layout)


func set_value(value: float, maximum: float) -> void:
	state.set_value(value, maximum)
	_bar.max_value = state.maximum
	_bar.value = state.target
	_refresh_label()
	_dirty = true


func set_marker_fraction(fraction: float) -> void:
	_marker_fraction = clampf(fraction, 0.0, 1.0)
	_dirty = true


func advance(delta: float, base_scale: Vector2 = Vector2.ONE) -> void:
	if not _dirty and not state.active() and base_scale == _base_scale and _bar.self_modulate.a == _blink_alpha:
		return
	state.advance(delta)
	_refresh_label()
	_base_scale = base_scale
	_blink_alpha = _bar.self_modulate.a
	position = _bar.position
	size = _bar.size
	pivot_offset = size * 0.5
	scale = base_scale
	_bar.pivot_offset = pivot_offset
	_bar.scale = scale
	_label.pivot_offset = _label.size * 0.5
	_label.scale = Vector2.ONE
	if _marker != null:
		_marker.pivot_offset = _marker.size * 0.5
		_marker.scale = scale
		_marker.position.x = position.x + size.x * 0.5 + size.x * (_marker_fraction - 0.5) * scale.x - _marker.size.x * 0.5
	visible = _bar.visible
	queue_redraw()
	_dirty = false


func _refresh_label() -> void:
	var text := "%d / %d" % [state.displayed, roundi(state.maximum)]
	if _label.text != text:
		_label.text = text


func _invalidate_layout() -> void:
	_dirty = true


func flash_rect() -> Rect2:
	var background := _bar.get_theme_stylebox("background")
	var left := background.get_margin(SIDE_LEFT)
	var right := background.get_margin(SIDE_RIGHT)
	var top := background.get_margin(SIDE_TOP)
	var bottom := background.get_margin(SIDE_BOTTOM)
	var width := maxf(0.0, size.x - left - right)
	var low := minf(state.target, state.trail) / state.maximum
	var high := maxf(state.target, state.trail) / state.maximum
	return Rect2(Vector2(left + width * low, top), Vector2(width * (high - low), maxf(0.0, size.y - top - bottom)))


func _draw() -> void:
	if _bar != null and state.white_alpha > 0.0:
		draw_rect(flash_rect(), Color(1.0, 1.0, 1.0, state.white_alpha * _blink_alpha))
