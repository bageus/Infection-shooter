extends Node3D
const SFX := preload("res://game/core/audio/public/sound_events.gd")

const FLASH := preload("res://models/objects/textures/grenade_explosion_layers/01_flash.png")
const FIRE := preload("res://models/objects/textures/grenade_explosion_layers/02_fireball.png")
const SHOCKWAVE := preload("res://models/objects/textures/grenade_explosion_layers/03_shockwave.png")
const SPARKS := preload("res://models/objects/textures/grenade_explosion_layers/04_sparks.png")
const SMOKE := preload("res://models/objects/textures/grenade_explosion_layers/05_smoke.png")
const PARTICLE_SHADER := preload("res://game/features/combat/grenade_explosion_particle.gdshader")

@export_range(0.5, 12.0, 0.1) var effect_radius := 7.8
@export_range(0.5, 4.0, 0.1) var effect_duration := 2.0
@export_range(1, 50, 1) var ember_count := 14
@export_range(1, 50, 1) var spark_count := 24
@export_range(1, 50, 1) var smoke_count := 15
@export_range(1, 20, 1) var debris_count := 7
@export_range(0.1, 12.0, 0.1) var flash_brightness := 4.8
@export_range(0.1, 2.0, 0.05) var smoke_size := 0.85

@onready var _flash: MeshInstance3D = $Flash
@onready var _fire: MeshInstance3D = $Fireball
@onready var _shockwave: MeshInstance3D = $Shockwave
@onready var _sparks: MeshInstance3D = $Sparks
@onready var _smoke: MeshInstance3D = $Smoke
@onready var _embers: GPUParticles3D = $FireEmbers
@onready var _spark_debris: GPUParticles3D = $SparkDebris
@onready var _wisps: GPUParticles3D = $SmokeWisps
@onready var _debris: GPUParticles3D = $Debris
@onready var _light: OmniLight3D = $ImpactLight
@onready var _sound: AudioStreamPlayer3D = $ExplosionSound

var _started := false


func _ready() -> void:
	_prepare_layer(_flash, FLASH, true, flash_brightness)
	_prepare_layer(_fire, FIRE, false, 1.0)
	_prepare_layer(_shockwave, SHOCKWAVE, false, 1.0)
	_prepare_layer(_sparks, SPARKS, true, 1.0)
	_prepare_layer(_smoke, SMOKE, false, 1.0)
	# Keep the pressure ring on the struck surface instead of facing the camera.
	(_shockwave.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED


func start(surface_normal: Vector3) -> void:
	if _started:
		return
	_started = true
	var outward := surface_normal.normalized() if surface_normal.length_squared() > 0.01 else Vector3.UP
	var speed := effect_duration / 2.0
	var size_scale := effect_radius / 2.6
	for layer in [_flash, _fire, _shockwave, _sparks, _smoke]:
		layer.position = outward * 0.08
	_flash.position = outward * 0.12
	_fire.position = outward * 0.11
	_smoke.position = outward * 0.16 + Vector3.UP * 0.16
	_embers.position = outward * 0.15 * size_scale
	_wisps.position = outward * 0.12 * size_scale
	_spark_debris.position = outward * 0.12
	_debris.position = outward * 0.12
	_shockwave.basis = Basis(Quaternion(Vector3.BACK, outward))
	_animate_layer(_flash, 0.0, 0.08, 0.35 * size_scale, 0.95 * size_scale, 0.65, speed)
	_animate_layer(_fire, 0.02, 0.36, 0.65 * size_scale, effect_radius * 0.68, 0.82, speed)
	_animate_layer(_shockwave, 0.045, 0.48, 0.55 * size_scale, effect_radius * 1.8, 0.4, speed)
	_animate_layer(_sparks, 0.04, 0.3, 0.7 * size_scale, effect_radius * 0.9, 0.12, speed)
	_animate_layer(_smoke, 0.24, 2.0, smoke_size * size_scale, effect_radius * 1.1, 0.14, speed)
	var smoke_rise := create_tween()
	smoke_rise.tween_property(_smoke, "position", _smoke.position + Vector3.UP * effect_radius * 0.2, 1.7 * speed).set_delay(0.24 * speed)
	_configure_emitter(_embers, FIRE, ember_count, 0.58 * speed, 0.6 * size_scale, effect_radius * 0.65,
		outward, 84.0, Vector3(0, 0.9, 0), Color(1, 0.88, 0.62), 0.85, 0.045)
	_configure_emitter(_spark_debris, SPARKS, spark_count, 0.68 * speed, 0.055 * size_scale, effect_radius * 1.8,
		outward, 88.0, Vector3(0, -7.0, 0), Color(1, 0.76, 0.3), 0.95, 0.0)
	_configure_emitter(_wisps, SMOKE, smoke_count, 1.7 * speed, smoke_size * size_scale, effect_radius * 0.32,
		outward.lerp(Vector3.UP, 0.45).normalized(), 78.0, Vector3(0, 0.8, 0), Color(0.52, 0.52, 0.5), 0.42, 0.035)
	_configure_debris(outward, size_scale, speed)
	_emit_after(_embers, 0.05 * speed)
	_emit_after(_spark_debris, 0.04 * speed)
	_emit_after(_wisps, 0.18 * speed)
	_emit_after(_debris, 0.07 * speed)
	_light.light_energy = flash_brightness
	_light.omni_range = effect_radius * 1.5
	var light_fade := create_tween()
	_light.light_color = Color(1.0, 0.85, 0.56)
	light_fade.tween_property(_light, "light_energy", flash_brightness * 0.35, 0.07 * speed)
	light_fade.parallel().tween_property(_light, "light_color", Color(1.0, 0.38, 0.08), 0.12 * speed)
	light_fade.tween_property(_light, "light_energy", 0.0, 0.19 * speed)
	SFX.play(get_parent() if get_parent() != null else self, &"grenade_explode", global_position)
	get_tree().create_timer(effect_duration + 0.2).timeout.connect(queue_free)


func _prepare_layer(layer: MeshInstance3D, texture: Texture2D, additive: bool, brightness: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	layer.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_texture = texture
		material.emission_energy_multiplier = brightness
	elif layer == _fire:
		material.emission_enabled = true
		material.emission_texture = texture
		material.emission = Color(1.0, 0.72, 0.3)
		material.emission_energy_multiplier = 1.8
	layer.material_override = material
	layer.visible = false


func _animate_layer(layer: MeshInstance3D, begin: float, finish: float,
		initial_size: float, final_size: float, opacity: float, time_scale: float) -> void:
	layer.scale = Vector3.ONE * initial_size
	var material := layer.material_override as StandardMaterial3D
	material.albedo_color = Color(1, 1, 1, opacity)
	var tween := create_tween()
	if begin > 0.0:
		tween.tween_interval(begin * time_scale)
	tween.tween_callback(layer.show)
	var span := (finish - begin) * time_scale
	tween.tween_property(layer, "scale", Vector3.ONE * final_size, span).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(material, "albedo_color", Color(1, 1, 1, 0), span * 0.88).set_delay(span * 0.12)
	tween.tween_callback(layer.hide)


func _configure_emitter(emitter: GPUParticles3D, texture: Texture2D, amount: int,
		lifetime: float, size: float, speed: float, direction: Vector3, spread: float,
		gravity: Vector3, tint: Color, opacity: float, drift: float) -> void:
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.local_coords = false
	emitter.explosiveness = 1.0
	emitter.randomness = 0.45
	emitter.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	if emitter == _spark_debris:
		emitter.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.visibility_aabb = AABB(Vector3.ONE * -effect_radius * 3.0, Vector3.ONE * effect_radius * 6.0)
	var motion := ParticleProcessMaterial.new()
	motion.lifetime_randomness = 0.3
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = effect_radius * 0.035
	motion.direction = direction
	motion.spread = spread
	motion.initial_velocity_min = speed * 0.55
	motion.initial_velocity_max = speed
	motion.gravity = gravity
	motion.damping_min = 0.4
	motion.damping_max = 1.2
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := ShaderMaterial.new()
	material.shader = PARTICLE_SHADER
	material.set_shader_parameter("particle_texture", texture)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("uv_drift", drift)
	material.set_shader_parameter("fire_particle", emitter == _embers)
	material.set_shader_parameter("spark_particle", emitter == _spark_debris)
	material.set_shader_parameter("growth", 2.6 if emitter == _wisps else 1.5)
	quad.material = material
	emitter.draw_pass_1 = quad


func _configure_debris(outward: Vector3, size_scale: float, time_scale: float) -> void:
	_debris.amount = debris_count
	_debris.lifetime = 0.9 * time_scale
	_debris.visibility_aabb = _spark_debris.visibility_aabb
	var motion := ParticleProcessMaterial.new()
	motion.lifetime_randomness = 0.35
	motion.particle_flag_rotate_y = true
	motion.direction = outward
	motion.spread = 85.0
	motion.initial_velocity_min = effect_radius * 0.35
	motion.initial_velocity_max = effect_radius * 0.9
	motion.gravity = Vector3(0, -9.8, 0)
	motion.angular_velocity_min = -380.0
	motion.angular_velocity_max = 380.0
	_debris.process_material = motion
	var fragment := BoxMesh.new()
	fragment.size = Vector3(0.045, 0.035, 0.075) * size_scale
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.13, 0.1)
	material.roughness = 0.9
	fragment.material = material
	_debris.draw_pass_1 = fragment


func _emit_after(emitter: GPUParticles3D, delay: float) -> void:
	# Binding the tween to the emitter cancels it when that emitter leaves the tree.
	var tween := emitter.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(emitter.restart)
	tween.tween_callback(emitter.set.bind("emitting", true))
