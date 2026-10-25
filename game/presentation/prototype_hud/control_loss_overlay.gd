extends ColorRect
## Screen filter while control is lost: light blur, a web of greenish capillaries and a
## centred countdown whose digits start small, grow and fade. The filter fades out
## gradually once control returns. Hidden (no shader cost) while idle.

const SHADER := preload("res://game/presentation/prototype_hud/control_loss_overlay.gdshader")
const FADE_IN_SPEED := 4.0
const FADE_OUT_SPEED := 0.8
const DIGIT_SIZE := 160
const DIGIT_START_SCALE := 0.45
const DIGIT_END_SCALE := 1.5

var _strength := 0.0
var _clock := 0.0
var _digit: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material_instance := ShaderMaterial.new()
	material_instance.shader = SHADER
	material = material_instance
	_digit = Label.new()
	_digit.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_digit.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_digit.grow_vertical = Control.GROW_DIRECTION_BOTH
	_digit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_digit.add_theme_font_size_override("font_size", DIGIT_SIZE)
	_digit.add_theme_color_override("font_color", Color(0.78, 1.0, 0.62))
	_digit.add_theme_color_override("font_outline_color", Color(0.05, 0.2, 0.04, 0.9))
	_digit.add_theme_constant_override("outline_size", 14)
	_digit.visible = false
	add_child(_digit)
	visible = false


## `remaining` is the seconds of control loss left; 0 while control is held.
func update(delta: float, remaining: float) -> void:
	var active := remaining > 0.0
	_strength = move_toward(_strength, 1.0 if active else 0.0, (FADE_IN_SPEED if active else FADE_OUT_SPEED) * delta)
	if _strength <= 0.001 and not active:
		_strength = 0.0
		visible = false
		return
	_clock += delta
	visible = true
	var shader_material := material as ShaderMaterial
	shader_material.set_shader_parameter("strength", _strength)
	shader_material.set_shader_parameter("clock", _clock)
	_digit.visible = active
	if active:
		_show_digit(remaining)


# The digit of the current whole second grows from small to large while fading in and out.
func _show_digit(remaining: float) -> void:
	var phase := 1.0 - (remaining - floorf(remaining)) if remaining != floorf(remaining) else 0.0
	var text := str(ceili(remaining))
	if _digit.text != text:
		_digit.text = text
		_digit.reset_size()
		_digit.pivot_offset = _digit.size * 0.5
		_digit.position = (size - _digit.size) * 0.5
	_digit.scale = Vector2.ONE * lerpf(DIGIT_START_SCALE, DIGIT_END_SCALE, phase)
	_digit.modulate.a = sin(phase * PI) * _strength
