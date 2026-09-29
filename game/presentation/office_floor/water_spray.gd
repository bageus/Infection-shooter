extends RefCounted

const DURATION := 10.0


static func spawn(host: Node3D, outlet: Vector3, reverse_direction: bool = false) -> void:
	var scene := host.get_tree().current_scene
	if scene == null:
		return
	var spray := GPUParticles3D.new()
	spray.name = "BrokenPipeWater"
	spray.amount = 76
	spray.lifetime = 0.9
	spray.explosiveness = 0.0
	spray.visibility_aabb = AABB(Vector3(-3, -4, -3), Vector3(6, 6, 6))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.035
	motion.direction = Vector3(0, 0.65, -1 if reverse_direction else 1).normalized()
	motion.spread = 38.0
	motion.initial_velocity_min = 1.8
	motion.initial_velocity_max = 3.5
	motion.gravity = Vector3(0, -9.8, 0)
	spray.process_material = motion
	var droplet := SphereMesh.new()
	droplet.radius = 0.025
	droplet.height = 0.085
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	float shimmer = 0.86 + 0.14 * sin(TIME * 23.0 + UV.y * 19.0);
	ALBEDO = vec3(0.28, 0.68, 0.92) * shimmer;
	EMISSION = vec3(0.06, 0.21, 0.32) * shimmer;
	ALPHA = 0.66;
}
"""
	var water_material := ShaderMaterial.new()
	water_material.shader = shader
	droplet.material = water_material
	spray.draw_pass_1 = droplet
	scene.add_child(spray)
	spray.global_position = outlet
	spray.emitting = true
	scene.get_tree().create_timer(DURATION).timeout.connect(func() -> void:
		if is_instance_valid(spray):
			spray.emitting = false
	)
	scene.get_tree().create_timer(DURATION + spray.lifetime + 0.2).timeout.connect(func() -> void:
		if is_instance_valid(spray):
			spray.queue_free()
	)
