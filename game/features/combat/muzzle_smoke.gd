extends RefCounted
## Thin translucent smoke at the muzzle while shooting: one reusable emitter per
## muzzle (8 quads, one draw call) that stops shortly after the last shot.
const SHADER := preload("res://game/core/vfx/public/smoke_puff.gdshader")
const EFFECTS_QUALITY := preload("res://game/core/vfx/public/effects_quality.gd")
const NAME := "MuzzleSmoke"
const STOP_AFTER := 0.12
static var _quad: QuadMesh


static func emit_at(anchor: Node3D, axis: Vector3) -> void:
	if not EFFECTS_QUALITY.at_least(EFFECTS_QUALITY.MEDIUM):
		return
	var particles := anchor.get_node_or_null(NAME) as GPUParticles3D
	if particles == null:
		particles = _create(axis)
		anchor.add_child(particles)
	particles.emitting = true
	var timer := particles.get_child(0) as Timer
	timer.start(STOP_AFTER)


static func _create(axis: Vector3) -> GPUParticles3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE * 0.17
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("opacity", 0.32)
		material.set_shader_parameter("growth", 2.6)
		material.set_shader_parameter("glow", 0.0)
		material.set_shader_parameter("smoke_color", Color(0.62, 0.61, 0.6))
		_quad.material = material
	var particles := GPUParticles3D.new()
	particles.name = NAME
	particles.amount = 8
	particles.lifetime = 0.7
	particles.local_coords = false
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_pass_1 = _quad
	particles.visibility_aabb = AABB(Vector3.ONE * -1.0, Vector3.ONE * 2.0)
	var motion := ParticleProcessMaterial.new()
	motion.direction = axis
	motion.spread = 18.0
	motion.initial_velocity_min = 0.15
	motion.initial_velocity_max = 0.45
	motion.gravity = Vector3.UP * 0.3
	particles.process_material = motion
	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(func() -> void: particles.emitting = false)
	particles.add_child(timer)
	return particles
