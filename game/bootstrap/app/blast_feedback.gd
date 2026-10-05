extends CanvasLayer
## Screen feedback follows the player's public stun lifecycle; UI stays sharp.
const SHADER := preload("res://game/bootstrap/app/blast_feedback.gdshader")
var actor: Node3D
var overlay: ColorRect
var material: ShaderMaterial
var remaining := 0.0
var duration := 0.0
var peak := 0.0
var phase := 0.0


func configure(player: Node3D) -> void:
	actor = player
	layer = -1
	process_mode = Node.PROCESS_MODE_PAUSABLE
	overlay = ColorRect.new()
	overlay.name = "BlastDistortion"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = SHADER
	overlay.material = material
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.hide()
	actor.connect("blast_stun_started", _on_started)
	actor.connect("blast_stun_ended", _on_ended)
	set_process(false)


func _on_started(seconds: float, intensity: float) -> void:
	remaining = maxf(0.0, seconds)
	duration = remaining
	peak = clampf(intensity, 0.0, 1.0)
	phase = 0.0
	_update_material()
	set_process(remaining > 0.0 and peak > 0.0)


func _process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)
	phase += delta
	_update_material()
	if remaining <= 0.0:
		_on_ended()


func _update_material() -> void:
	# Last second fades smoothly; no full-screen flash or brightness boost.
	var envelope := smoothstep(0.0, minf(1.0, duration), remaining)
	material.set_shader_parameter("strength", peak * envelope)
	material.set_shader_parameter("phase", phase)
	overlay.visible = remaining > 0.0 and peak > 0.0


func _on_ended() -> void:
	remaining = 0.0
	peak = 0.0
	if is_instance_valid(overlay):
		overlay.hide()
		material.set_shader_parameter("strength", 0.0)
	set_process(false)


func _exit_tree() -> void:
	if is_instance_valid(actor):
		if actor.is_connected("blast_stun_started", _on_started):
			actor.disconnect("blast_stun_started", _on_started)
			actor.disconnect("blast_stun_ended", _on_ended)
