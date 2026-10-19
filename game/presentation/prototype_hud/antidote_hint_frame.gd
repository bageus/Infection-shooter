extends Control
## Translucent frame that starts at the screen edges, snaps in onto the antidote cell,
## holds there and fades out. The HUD plays it after a control loss, repeating it for the Nth loss.

const PALETTE := preload("res://game/presentation/prototype_hud/hud_palette.gd")
const LINE_WIDTH := 2.0
const EDGE_INSET := 4.0
const FOCUS_SECONDS := 0.3
const HOLD_SECONDS := 2.5
const FADE_SECONDS := 1.1
const LINE_COLOR := Color(PALETTE.INK, 0.6)

var passes_started := 0
var _screen := Rect2()
var _target := Rect2()
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LINE_COLOR, false, LINE_WIDTH)


# Plays `repeats` passes back to back; each pass begins only after the previous frame has faded out.
func play(target: Rect2, repeats: int) -> void:
	if _tween != null:
		_tween.kill()
	_target = target.grow(EDGE_INSET)
	_screen = get_viewport().get_visible_rect().grow(-EDGE_INSET)
	passes_started = 0
	_tween = create_tween().set_loops(repeats)
	_tween.tween_callback(_begin_pass)
	_tween.tween_method(_set_focus, 0.0, 1.0, FOCUS_SECONDS).set_ease(Tween.EASE_IN)
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(hide)


func _begin_pass() -> void:
	passes_started += 1
	modulate.a = 1.0
	_set_focus(0.0)
	visible = true


func _set_focus(progress: float) -> void:
	position = _screen.position.lerp(_target.position, progress)
	size = _screen.size.lerp(_target.size, progress)
	queue_redraw()
