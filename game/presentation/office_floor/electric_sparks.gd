extends RefCounted

const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")

# First hit on a device: the six-frame spark sheet bursts at the hit point and
# crackles on for a moment near it (2-3 short bursts), with a blue-white flash
# and a spray of particles. Sprites follow the device if it is knocked about.
static func short_circuit(host: Node3D, location: Vector3, normal: Vector3 = Vector3.ZERO) -> void:
	var outward := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	spawn(host, location, false)
	_flash(host, location + outward * 0.05)
	if not ATLASES.available(ATLASES.ELECTRIC_SPARK):
		return
	_burst(host, location + outward * 0.03, 0.34)
	var tree := host.get_tree()
	var device: WeakRef = weakref(host)
	for i in randi_range(2, 3):
		var offset := Vector3(randf_range(-0.12, 0.12), randf_range(-0.08, 0.12), randf_range(-0.12, 0.12))
		tree.create_timer(randf_range(0.12, 0.75)).timeout.connect(func() -> void:
			var live := device.get_ref() as Node3D
			if live != null and live.is_inside_tree():
				_burst(live, location + outward * 0.03 + offset, randf_range(0.2, 0.3)))


static func _burst(host: Node3D, location: Vector3, size: float) -> void:
	FLIPBOOK.spawn(host, ATLASES.ELECTRIC_SPARK, location, size, {
		"additive": 1.0, "brightness": 2.4, "spin": randf() * TAU, "speed": randf_range(0.9, 1.15),
	})


static func _flash(host: Node3D, location: Vector3) -> void:
	var container := host.get("effects_root") as Node3D
	if not is_instance_valid(container):
		return
	var light := OmniLight3D.new()
	light.name = "SparkFlash"
	light.light_color = Color(0.7, 0.85, 1.0)
	light.light_energy = 2.2
	light.omni_range = 1.6
	light.shadow_enabled = false
	container.add_child(light)
	light.global_position = location
	var fade := light.create_tween()
	fade.tween_property(light, "light_energy", 0.0, 0.12)
	fade.tween_callback(light.queue_free)


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
