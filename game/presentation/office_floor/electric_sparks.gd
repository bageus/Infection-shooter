extends RefCounted

# One-shot GPU particles remain in world coordinates when the damaged prop moves.
static func spawn(host: Node3D, location: Vector3, heavy: bool = false) -> void:
	var container := host.get("effects_root") as Node3D
	if not is_instance_valid(container):
		return
	var particles := GPUParticles3D.new()
	particles.name = "ElectricalSparks"
	particles.amount = 22 if heavy else 9
	particles.lifetime = 0.38
	particles.one_shot = true
	particles.explosiveness = 1.0
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.08
	process.direction = Vector3.UP
	process.spread = 110.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 4.0 if heavy else 2.7
	process.gravity = Vector3(0, -7, 0)
	particles.process_material = process
	var dot := SphereMesh.new()
	dot.radius = 0.015
	dot.height = 0.03
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1, 0.73, 0.15)
	glow.emission_enabled = true
	glow.emission = Color(1, 0.48, 0.06)
	glow.emission_energy_multiplier = 5.0
	dot.material = glow
	particles.draw_pass_1 = dot
	container.add_child(particles)
	particles.global_position = location
	particles.emitting = true
	host.get_tree().create_timer(1.2).timeout.connect(particles.queue_free)
