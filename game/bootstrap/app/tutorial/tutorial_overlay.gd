extends CanvasLayer
## Plays one tutorial step at a time: dims the screen except the spotlit rectangles,
## outlines them, optionally points an arrow, and shows a short text.
## A "click" step pauses the game and ends on any key or mouse press.
## A "wait" step lets input through and ends when its `done` callable returns true.
## Step keys: text, targets (Array of Callable -> Rect2), mode, arrow, picture (+ mutation, threshold),
## hint (text at the top, no dim), dim, requires, done.

const PALETTE := preload("res://game/bootstrap/app/tutorial/tutorial_palette.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const SPOTLIGHT := preload("res://game/bootstrap/app/tutorial/tutorial_spotlight.gdshader")
const PICTURE := preload("res://game/bootstrap/app/tutorial/tutorial_meter_picture.gd")
const TITLE_FONT := preload("res://assets/interface/fonts/title.ttf")
const GROW := 8.0
const MIN_STEP_SECONDS := 0.3
const TEXT_WIDTH := 460.0

signal step_finished

var active := false
var step: Dictionary = {}
var picture: Control
var _dim: ColorRect
var _frame: Control
var _panel: PanelContainer
var _label: Label
var _footer: Label
var _holes: Array[Rect2] = []
var _started_ms := 0
var _paused_by_overlay := false


func _init() -> void:
	layer = 130
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.material = ShaderMaterial.new()
	(_dim.material as ShaderMaterial).shader = SPOTLIGHT
	add_child(_dim)
	_frame = Control.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_frame)
	add_child(_frame)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PALETTE.PANEL
	style.border_color = PALETTE.BORDER
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	picture = PICTURE.new()
	column.add_child(picture)
	_label = Label.new()
	_label.custom_minimum_size.x = TEXT_WIDTH
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_override("font", TITLE_FONT)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_color", PALETTE.INK)
	column.add_child(_label)
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 11)
	_footer.add_theme_color_override("font_color", PALETTE.FAINT)
	column.add_child(_footer)
	add_child(_panel)


func play(next_step: Dictionary) -> void:
	finish(false)
	step = next_step
	active = true
	_started_ms = Time.get_ticks_msec()
	_label.text = str(step.get("text", ""))
	picture.visible = bool(step.get("picture", false))
	picture.set("mutation", float(step.get("mutation", 0.0)))
	picture.set("threshold", float(step.get("threshold", 30.0)))
	picture.queue_redraw()
	_footer.text = TEXT.t("tutContinue") if _is_click() else ""
	_footer.visible = _is_click()
	_refresh()


## Ends the step; `notify` false is used when a new step replaces it.
func finish(notify: bool = true) -> void:
	if not active:
		return
	active = false
	visible = false
	_release_pause()
	if notify:
		step_finished.emit()


func _is_click() -> bool:
	return str(step.get("mode", "click")) == "click"


func _process(_delta: float) -> void:
	if not active:
		return
	var done: Callable = step.get("done", Callable())
	if not _is_click() and done.is_valid() and bool(done.call()):
		finish()
		return
	_refresh()


func _refresh() -> void:
	var requires: Callable = step.get("requires", Callable())
	var ready := not requires.is_valid() or bool(requires.call())
	visible = ready
	if not ready:
		_release_pause()
		return
	if _is_click() and not get_tree().paused:
		get_tree().paused = true
		_paused_by_overlay = true
	_collect_holes()
	var material := _dim.material as ShaderMaterial
	var packed := PackedVector4Array()
	for index in 4:
		var hole := _holes[index] if index < _holes.size() else Rect2()
		packed.append(Vector4(hole.position.x, hole.position.y, hole.size.x, hole.size.y))
	material.set_shader_parameter("holes", packed)
	material.set_shader_parameter("hole_count", _holes.size())
	material.set_shader_parameter("screen_size", get_viewport().get_visible_rect().size)
	material.set_shader_parameter("dim_color", Color(0.03, 0.04, 0.05, 0.82 if bool(step.get("dim", true)) else 0.0))
	_place_panel()
	_frame.queue_redraw()


func _collect_holes() -> void:
	_holes.clear()
	for target: Callable in step.get("targets", []):
		var rect: Rect2 = target.call()
		if rect.size.x > 0.0 and rect.size.y > 0.0 and _holes.size() < 4:
			_holes.append(rect.grow(GROW))


func _place_panel() -> void:
	var screen := get_viewport().get_visible_rect().size
	var panel_size := _panel.get_combined_minimum_size()
	_panel.size = panel_size
	var position := (screen - panel_size) * 0.5
	if bool(step.get("hint", false)):
		position = Vector2(position.x, 72.0)
	elif not _holes.is_empty():
		var area := _holes[0]
		for hole in _holes:
			area = area.merge(hole)
		position.x = clampf(area.get_center().x - panel_size.x * 0.5, 12.0, screen.x - panel_size.x - 12.0)
		position.y = area.end.y + 28.0 if area.get_center().y < screen.y * 0.55 else area.position.y - panel_size.y - 28.0
		position.y = clampf(position.y, 12.0, screen.y - panel_size.y - 12.0)
	_panel.position = position


func _draw_frame() -> void:
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.006)
	for hole in _holes:
		_frame.draw_rect(hole, Color(PALETTE.INK, pulse), false, 2.0)
	if bool(step.get("arrow", false)) and not _holes.is_empty():
		var tip := Vector2(_holes[0].position.x - 6.0, _holes[0].get_center().y)
		_frame.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-34, -20), tip + Vector2(-34, 20)]), Color(PALETTE.KEY_GOLD, pulse))


func _input(event: InputEvent) -> void:
	if not active or not visible or not _is_click():
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.is_echo()) or (event is InputEventMouseButton and event.pressed)
	if not pressed or Time.get_ticks_msec() - _started_ms < int(MIN_STEP_SECONDS * 1000.0):
		return
	get_viewport().set_input_as_handled()
	finish()


func _release_pause() -> void:
	if _paused_by_overlay:
		_paused_by_overlay = false
		get_tree().paused = false
