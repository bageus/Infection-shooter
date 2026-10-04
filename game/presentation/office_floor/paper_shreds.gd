extends RefCounted
## Torn paper: a shot paper object is destroyed completely and bursts into
## 5-6 scraps picked at random from the ten-frame torn paper sheet. The scraps
## tumble and flutter down like a ripped sheet; fine shreds fill in between.

const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
const PAPER_WORDS := ["paper", "notepad", "office_file", "document", "envelope", "newspaper", "magazine", "letter"]


static func is_paper(model_path: String) -> bool:
	var file := model_path.get_file().to_lower()
	for word in PAPER_WORDS:
		if word in file:
			return true
	return false


static func tear(host: Node3D, hit_position: Vector3, direction: Vector3) -> void:
	var scene := host.get("effects_root") as Node3D
	if not is_instance_valid(scene):
		return
	if not ATLASES.available(ATLASES.TORN_PAPER):
		spawn(host, hit_position, direction)
		return
	var push := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO
	var frames := range(int(ATLASES.TORN_PAPER["frames"]))
	frames.shuffle()
	for i in randi_range(5, 6):
		var spread := Vector3(randf_range(-1.0, 1.0), randf_range(0.35, 1.0), randf_range(-1.0, 1.0)).normalized()
		var velocity := (spread * randf_range(0.9, 2.2) + push * randf_range(0.4, 1.4))
		FLIPBOOK.spawn(scene, ATLASES.TORN_PAPER, hit_position + spread * 0.04, randf_range(0.11, 0.2), {
			"billboard": false, "frame": frames[i], "lifetime": randf_range(1.9, 2.8), "fade_out": 0.6,
			"velocity": velocity, "gravity": 3.2, "drag": 2.1, "spin": randf() * TAU,
			"tumble": Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * randf_range(5.0, 11.0),
		})
	spawn(host, hit_position, direction, 14)


static func spawn(host: Node3D, hit_position: Vector3, direction: Vector3, amount: int = 38) -> void:
	var scene := host.get("effects_root") as Node3D
	if not is_instance_valid(scene):
		return
	var shreds := GPUParticles3D.new()
	shreds.name = "TornPaper"
	shreds.amount = amount
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
	scene.get_tree().create_timer(shreds.lifetime + 0.35).timeout.connect(shreds.queue_free)
