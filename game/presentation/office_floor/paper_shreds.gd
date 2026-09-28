extends RefCounted


static func spawn(host: Node3D, hit_position: Vector3, direction: Vector3) -> void:
	var scene := host.get_tree().current_scene
	if scene == null:
		return
	var shreds := GPUParticles3D.new()
	shreds.name = "TornPaper"
	shreds.amount = 38
	shreds.lifetime = 1.65
	shreds.one_shot = true
	shreds.explosiveness = 1.0
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.075
	motion.direction = (direction.normalized() + Vector3.UP * 0.7).normalized()
	motion.spread = 100.0
	motion.initial_velocity_min = 0.55
	motion.initial_velocity_max = 2.2
	motion.gravity = Vector3(0, -3.7, 0)
	motion.angular_velocity_min = -450.0
	motion.angular_velocity_max = 450.0
	shreds.process_material = motion
	var scrap := QuadMesh.new()
	scrap.size = Vector2(0.085, 0.065)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	float edge_x = 0.06 + 0.035 * sin(UV.y * 31.0 + UV.x * 13.0);
	float edge_y = 0.06 + 0.035 * sin(UV.x * 29.0 + UV.y * 11.0);
	float cut = step(edge_x, UV.x) * step(edge_x, 1.0 - UV.x)
		* step(edge_y, UV.y) * step(edge_y, 1.0 - UV.y);
	float fiber = 0.93 + 0.07 * sin(UV.x * 52.0 + UV.y * 41.0);
	ALBEDO = vec3(0.88, 0.86, 0.79) * fiber;
	ALPHA = cut * 0.95;
}
"""
	var paper_material := ShaderMaterial.new()
	paper_material.shader = shader
	scrap.material = paper_material
	shreds.draw_pass_1 = scrap
	scene.add_child(shreds)
	shreds.global_position = hit_position
	shreds.emitting = true
	scene.get_tree().create_timer(shreds.lifetime + 0.35).timeout.connect(func() -> void:
		if is_instance_valid(shreds):
			shreds.queue_free()
	)
