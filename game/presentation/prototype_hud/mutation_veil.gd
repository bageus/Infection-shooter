extends ColorRect
## Full-screen green haze shown from the second loss of control until the run ends.
## Fades in and out smoothly; mouse input passes through.

const SHADER := preload("res://game/presentation/prototype_hud/mutation_veil.gdshader")
const FADE_SPEED := 1.2

var _strength := 0.0
var _clock := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material_instance := ShaderMaterial.new()
	material_instance.shader = SHADER
	material = material_instance
	visible = false


func update(delta: float, active: bool) -> void:
	_strength = move_toward(_strength, 1.0 if active else 0.0, FADE_SPEED * delta)
	if _strength <= 0.001 and not active:
		_strength = 0.0
		visible = false
		return
	_clock += delta
	visible = true
	(material as ShaderMaterial).set_shader_parameter("strength", _strength)
	(material as ShaderMaterial).set_shader_parameter("clock", _clock)
