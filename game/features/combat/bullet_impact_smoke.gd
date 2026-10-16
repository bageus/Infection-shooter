extends Node3D
## Mission-local short-lived cold dust; no lights and no texture allocation.
const SHADER := preload("res://game/core/vfx/public/smoke_puff.gdshader")
const MAX_PUFFS := 16
const PER_FRAME := 2
const LIFETIME := 0.45
var _live: Array[GPUParticles3D] = []
var _frame := -1
var _admitted := 0
var _quad: QuadMesh


func puff(point: Vector3, normal: Vector3) -> void:
	var frame := Engine.get_physics_frames()
	if frame != _frame:
		_frame = frame
		_admitted = 0
	for i in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[i]) or _live[i].is_queued_for_deletion():
			_live.remove_at(i)
	if _admitted >= PER_FRAME or _live.size() >= MAX_PUFFS:
		return
	_admitted += 1
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE * 0.18
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("opacity", 0.32)
		material.set_shader_parameter("growth", 2.0)
		material.set_shader_parameter("glow", 0.0)
		material.set_shader_parameter("smoke_color", Color(0.52, 0.50, 0.47))
		_quad.material = material
	var particles := GPUParticles3D.new()
	particles.amount = 3
	particles.lifetime = LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_pass_1 = _quad
	particles.visibility_aabb = AABB(Vector3.ONE * -0.6, Vector3.ONE * 1.2)
	var motion := ParticleProcessMaterial.new()
	motion.direction = normal.normalized()
	motion.spread = 24.0
	motion.initial_velocity_min = 0.25
	motion.initial_velocity_max = 0.6
	motion.gravity = Vector3.UP * 0.25
	particles.process_material = motion
	particles.emitting = false
	add_child(particles)
	particles.global_position = point + normal.normalized() * 0.025
	_live.append(particles)
	particles.emitting = true
	# A finite timer also cleans up on headless renderers without particle updates.
	get_tree().create_timer(LIFETIME + 0.1, false).timeout.connect(particles.queue_free)


func clear() -> void:
	for particles in _live:
		if is_instance_valid(particles):
			particles.queue_free()
	_live.clear()
