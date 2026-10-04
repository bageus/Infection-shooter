extends Node3D
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")

const SHADER := preload("res://game/presentation/office_floor/extinguisher_particle.gdshader")
const TEXTURE := preload("res://models/objects/textures/extinguisher_spray.png")

@onready var _flash: OmniLight3D = $Flash
@onready var _ring: MeshInstance3D = $PressureRing
@onready var _burst: GPUParticles3D = $PowderBurst
@onready var _cloud: GPUParticles3D = $PowderCloud
@onready var _pop: AudioStreamPlayer3D = $Pop

var _radius := 3.0
var _elapsed := 0.0
var _cloud_lifetime := 3.6

var effects_root: Node3D
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 1.0
	_ring.mesh = torus
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = Color(0.88, 0.93, 0.96, 0.65)
	_ring.material_override = ring_material
	_ring.scale = Vector3.ONE * 0.08
	_ring.visible = false
	set_process(false)


func start(radius: float, cloud_lifetime: float, burst_count: int) -> void:
	_radius = radius
	_cloud_lifetime = cloud_lifetime
	_elapsed = 0.0
	_setup_particles(_burst, burst_count, 0.85, 2.0, 4.5, 0.3, 0.44)
	var drift := radius / maxf(cloud_lifetime, 0.1)
	_setup_particles(_cloud, maxi(24, floori(float(burst_count) * 0.5)), cloud_lifetime,
		drift * 0.45, drift * 1.2, 0.88, 0.32)
	_burst.restart()
	_burst.emitting = true
	_cloud.restart()
	_cloud.emitting = true
	_ring.visible = true
	_flash.light_energy = 5.0
	SFX.play(get_parent() if get_parent() != null else self, &"extinguisher_burst", global_position)
	# Rupture cloud from the extinguisher sheet: a burst of powder swelling out.
	for i in 3:
		var offset := Vector3(randf_range(-0.3, 0.3), randf_range(0.1, 0.5), randf_range(-0.3, 0.3))
		FLIPBOOK.spawn(self, ATLASES.EXTINGUISHER_SPRAY, global_position + offset, radius * randf_range(0.45, 0.6), {
			"grow": randf_range(1.6, 2.1), "spin": randf() * TAU, "spin_speed": randf_range(-0.4, 0.4),
			"speed": randf_range(0.55, 0.7), "fade_out": 0.8, "velocity": offset * 0.8, "drag": 1.2, "gravity": -0.15,
		})
	_spawn_fragments()
	set_process(true)
	get_tree().create_timer(_cloud_lifetime + 1.0).timeout.connect(queue_free)


func _process(delta: float) -> void:
	_elapsed += delta
	var ring_progress := clampf(_elapsed / 0.42, 0.0, 1.0)
	_ring.scale = Vector3.ONE * lerpf(0.08, _radius, ring_progress)
	var material := _ring.material_override as StandardMaterial3D
	material.albedo_color.a = 0.65 * (1.0 - ring_progress)
	_ring.visible = ring_progress < 1.0
	_flash.light_energy = 5.0 * (1.0 - clampf(_elapsed / 0.16, 0.0, 1.0))
	if _elapsed >= 0.42:
		set_process(false)


func _setup_particles(emitter: GPUParticles3D, amount: int, lifetime: float,
		low_speed: float, high_speed: float, size: float, opacity: float) -> void:
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.local_coords = false
	emitter.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	emitter.visibility_aabb = AABB(Vector3.ONE * -8.0, Vector3.ONE * 16.0)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.18
	motion.direction = Vector3.UP
	motion.spread = 180.0
	motion.initial_velocity_min = low_speed
	motion.initial_velocity_max = high_speed
	motion.gravity = Vector3(0.0, -0.12, 0.0)
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("spray_texture", TEXTURE)
	material.set_shader_parameter("opacity", opacity)
	quad.material = material
	emitter.draw_pass_1 = quad


func _spawn_fragments() -> void:
	var world := effects_root
	if not is_instance_valid(world):
		return
	for index in 7:
		var piece := RigidBody3D.new()
		piece.name = "ExtinguisherFragment"
		piece.mass = 0.09
		piece.collision_layer = 0
		piece.collision_mask = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.08, 0.14, 0.045)
		shape.shape = box
		piece.add_child(shape)
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = box.size
		visual.mesh = mesh
		var surface := StandardMaterial3D.new()
		surface.albedo_color = Color(0.72, 0.05, 0.045) if index % 3 == 0 else Color(0.58, 0.62, 0.65)
		visual.material_override = surface
		piece.add_child(visual)
		world.add_child(piece)
		piece.global_position = global_position + Vector3(randf_range(-0.12, 0.12), randf_range(-0.1, 0.2), randf_range(-0.12, 0.12))
		piece.apply_central_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(0.45, 1.25), randf_range(-1.0, 1.0)).normalized() * randf_range(0.2, 0.5))
		piece.apply_torque_impulse(Vector3(randf_range(-0.08, 0.08), randf_range(-0.08, 0.08), randf_range(-0.08, 0.08)))
		get_tree().create_timer(5.0).timeout.connect(piece.queue_free)
