extends CanvasLayer
## Player death: the screen blurs and sinks to black, then `finished` fires once.
signal finished
const SHADER := preload("res://game/bootstrap/app/death_fade.gdshader")
## Seconds between the lethal hit and the defeat menu (owner asked for 2-5).
const DURATION := 3.0
var elapsed := 0.0
var _done := false
var _material := ShaderMaterial.new()


func _ready() -> void:
	layer = 100 # above the HUD, below the menus (200)
	_material.shader = SHADER
	var overlay := ColorRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.material = _material
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	elapsed += delta
	_material.set_shader_parameter("progress", clampf(elapsed / DURATION, 0.0, 1.0))
	if elapsed >= DURATION and not _done:
		_done = true
		finished.emit()
