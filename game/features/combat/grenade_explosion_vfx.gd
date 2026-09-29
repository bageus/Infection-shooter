extends Node3D

const FLASH := preload("res://models/objects/textures/grenade_explosion_layers/01_flash.png")
const FIRE := preload("res://models/objects/textures/grenade_explosion_layers/02_fireball.png")
const SHOCKWAVE := preload("res://models/objects/textures/grenade_explosion_layers/03_shockwave.png")
const SPARKS := preload("res://models/objects/textures/grenade_explosion_layers/04_sparks.png")
const SMOKE := preload("res://models/objects/textures/grenade_explosion_layers/05_smoke.png")
const PARTICLE_SHADER := preload("res://game/features/combat/grenade_explosion_particle.gdshader")

@export_range(0.5, 6.0, 0.1) var effect_radius := 2.6
@export_range(0.5, 4.0, 0.1) var effect_duration := 2.0
@export_range(1, 50, 1) var ember_count := 8
@export_range(1, 50, 1) var spark_count := 12
@export_range(1, 50, 1) var smoke_count := 7
@export_range(0.1, 6.0, 0.1) var flash_brightness := 2.5
@export_range(0.1, 2.0, 0.05) var smoke_size := 0.65

@onready var _flash: MeshInstance3D = $Flash
@onready var _fire: MeshInstance3D = $Fireball
@onready var _shockwave: MeshInstance3D = $Shockwave
@onready var _sparks: MeshInstance3D = $Sparks
@onready var _smoke: MeshInstance3D = $Smoke
@onready var _embers: GPUParticles3D = $FireEmbers
@onready var _spark_debris: GPUParticles3D = $SparkDebris
@onready var _wisps: GPUParticles3D = $SmokeWisps
@onready var _light: OmniLight3D = $ImpactLight
@onready var _sound: AudioStreamPlayer3D = $ExplosionSound

var _started := false


func _ready() -> void:
	_prepare_layer(_flash, FLASH, true, flash_brightness)
	_prepare_layer(_fire, FIRE, false, 1.0)
	_prepare_layer(_shockwave, SHOCKWAVE, false, 1.0)
	_prepare_layer(_sparks, SPARKS, true, 1.0)
	_prepare_layer(_smoke, SMOKE, false, 1.0)


func start(surface_normal: Vector3) -> void:
	if _started:
		return
	_started = true
	var outward := surface_normal.normalized() if surface_normal.length_squared() > 0.01 else Vector3.UP
	var speed := effect_duration / 2.0
	for layer in [_flash, _fire, _shockwave, _sparks, _smoke]:
		layer.position = outward * 0.08
	_flash.position = outward * 0.12
	_fire.position = outward * 0.11
	_smoke.position = outward * 0.16 + Vector3.UP * 0.16
	_animate_layer(_flash, 0.0, 0.1, 0.35, 0.8, 0.42, speed)
	_animate_layer(_fire, 0.03, 0.4, 0.65, effect_radius * 0.75, 0.7, speed)
	_animate_layer(_shockwave, 0.05, 0.55, 0.55, effect_radius * 1.8, 0.52, speed)
	_animate_layer(_sparks, 0.04, 0.65, 0.7, effect_radius * 0.9, 0.22, speed)
	_animate_layer(_smoke, 0.18, 2.0, smoke_size, effect_radius * 1.25, 0.38, speed)
	_configure_emitter(_embers, FIRE, ember_count, 0.36 * speed, 0.16, effect_radius * 1.1,
		outward, 80.0, Vector3(0, -2.2, 0), Color(1, 0.57, 0.2), 0.52, 0.0)
	_configure_emitter(_spark_debris, SPARKS, spark_count, 0.58 * speed, 0.12, effect_radius * 2.4,
		outward, 86.0, Vector3(0, -4.0, 0), Color(1, 0.78, 0.36), 0.55, 0.0)
	_configure_emitter(_wisps, SMOKE, smoke_count, 1.8 * speed, smoke_size * 0.75, effect_radius * 0.5,
		Vector3.UP, 75.0, Vector3(0, 0.36, 0), Color(0.7, 0.7, 0.68), 0.24, 0.025)
	_emit_after(_embers, 0.05 * speed)
	_emit_after(_spark_debris, 0.04 * speed)
	_emit_after(_wisps, 0.18 * speed)
	_light.light_energy = flash_brightness
	var light_fade := create_tween()
	light_fade.tween_property(_light, "light_energy", 0.0, 0.12 * speed)
	_sound.play()
	get_tree().create_timer(maxf(effect_duration + 0.2, _sound.stream.get_length() + 0.1)).timeout.connect(queue_free)


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
	tween.tween_property(layer, "scale", Vector3.ONE * final_size, span)
	tween.parallel().tween_property(material, "albedo_color", Color(1, 1, 1, 0), span)
	tween.tween_callback(layer.hide)


func _configure_emitter(emitter: GPUParticles3D, texture: Texture2D, amount: int,
		lifetime: float, size: float, speed: float, direction: Vector3, spread: float,
		gravity: Vector3, tint: Color, opacity: float, drift: float) -> void:
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.local_coords = false
	emitter.explosiveness = 1.0
	emitter.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	emitter.visibility_aabb = AABB(Vector3.ONE * -8.0, Vector3.ONE * 16.0)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	motion.direction = direction
	motion.spread = spread
	motion.initial_velocity_min = speed * 0.55
	motion.initial_velocity_max = speed
	motion.gravity = gravity
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	var material := ShaderMaterial.new()
	material.shader = PARTICLE_SHADER
	material.set_shader_parameter("particle_texture", texture)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("uv_drift", drift)
	quad.material = material
	emitter.draw_pass_1 = quad


func _emit_after(emitter: GPUParticles3D, delay: float) -> void:
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void:
		emitter.restart()
		emitter.emitting = true
	)
