extends "res://game/features/combat/grenade_explosion_vfx.gd"

const FIRE_ATLAS_PATH := "res://models/objects/textures/grenade_explosion_layers.png"
const ATLAS_SHADER := preload("res://game/features/combat/grenade_explosion_atlas.gdshader")
const FRAME_COUNT := 16

@export_range(0.03, 0.06, 0.005) var flash_seconds := 0.05
@export_range(0.1, 0.2, 0.01) var fire_seconds := 0.18
@export_range(0, 16, 1) var atlas_columns := 0 # 0 detects a grid of square frames.
@export_range(1, 50, 1) var dust_count := 22

@onready var _dust: GPUParticles3D = $Dust

var _atlas_material: ShaderMaterial


func _ready() -> void:
	super._ready()
	var atlas := load(FIRE_ATLAS_PATH) as Texture2D
	if atlas == null:
		push_error("Explosion 2 atlas is missing: " + FIRE_ATLAS_PATH)
		return
	var dimensions := atlas.get_size()
	var columns := atlas_columns
	if columns == 0:
		columns = clampi(roundi(sqrt(FRAME_COUNT * dimensions.x / maxf(dimensions.y, 1.0))), 1, FRAME_COUNT)
	if FRAME_COUNT % columns != 0:
		push_warning("Explosion atlas grid could not be inferred; using 4 x 4. Set atlas_columns explicitly.")
		columns = 4
	_atlas_material = ShaderMaterial.new()
	_atlas_material.shader = ATLAS_SHADER
	_atlas_material.set_shader_parameter("fire_atlas", atlas)
	_atlas_material.set_shader_parameter("grid", Vector2(float(columns), float(FRAME_COUNT) / float(columns)))
	_fire.material_override = _atlas_material


func start(surface_normal: Vector3) -> void:
	if _started:
		return
	if _atlas_material == null:
		# Keep a readable effect if an incomplete local checkout lacks the atlas.
		super.start(surface_normal)
		return
	_started = true
	var outward := surface_normal.normalized() if surface_normal.length_squared() > 0.01 else Vector3.UP
	var size_scale := effect_radius / 2.6
	_flash.position = outward * 0.12
	_fire.position = outward * 0.2
	_wisps.position = outward * 0.2
	_spark_debris.position = outward * 0.14
	_debris.position = outward * 0.14
	_animate_layer(_flash, 0.0, flash_seconds, 0.25 * size_scale, 0.8 * size_scale, 0.65, 1.0)
	_animate_fire(size_scale)
	_configure_emitter(_spark_debris, SPARKS, spark_count, 0.65, 0.045 * size_scale,
		effect_radius * 1.4, outward, 86.0, Vector3(0, -8, 0), Color(1, 0.72, 0.25), 0.9, 0.0)
	_configure_clouds(outward, size_scale)
	_configure_debris(outward, size_scale, 1.0)
	var debris_motion := _debris.process_material as ParticleProcessMaterial
	debris_motion.damping_min = 0.8
	debris_motion.damping_max = 1.6
	_emit_after(_spark_debris, 0.025)
	_emit_after(_debris, 0.03)
	_emit_after(_dust, 0.075)
	_emit_after(_wisps, 0.14)
	_light.light_color = Color(1.0, 0.86, 0.6)
	_light.omni_range = effect_radius
	_light.light_energy = flash_brightness
	var light_fade := create_tween()
	light_fade.tween_property(_light, "light_energy", flash_brightness * 0.2, flash_seconds)
	light_fade.parallel().tween_property(_light, "light_color", Color(1.0, 0.45, 0.15), flash_seconds)
	light_fade.tween_property(_light, "light_energy", 0.0, fire_seconds - flash_seconds)
	_sound.play()
	get_tree().create_timer(maxf(effect_duration + 0.3, _sound.stream.get_length() + 0.1)).timeout.connect(queue_free)


func _configure_clouds(outward: Vector3, size_scale: float) -> void:
	_configure_emitter(_wisps, SMOKE, smoke_count, effect_duration - 0.2, smoke_size * size_scale * 0.65,
		effect_radius * 0.2, outward.lerp(Vector3.UP, 0.55).normalized(), 75.0,
		Vector3(0, 0.65, 0), Color(0.56, 0.56, 0.54), 0.4, 0.035)
	_configure_emitter(_dust, SMOKE, dust_count, 0.9, 0.35 * size_scale, effect_radius * 0.5,
		Vector3.RIGHT, 180.0, Vector3(0, 0.12, 0), Color(0.64, 0.55, 0.43), 0.24, 0.035)
	_dust.position = outward * 0.1
	_dust.basis = Basis(Quaternion(Vector3.UP, outward))
	var dust_motion := _dust.process_material as ParticleProcessMaterial
	dust_motion.flatness = 1.0
	dust_motion.damping_min = 2.5
	dust_motion.damping_max = 5.0
	var dust_quad := _dust.draw_pass_1 as QuadMesh
	(dust_quad.material as ShaderMaterial).set_shader_parameter("growth", 2.8)


func _animate_fire(size_scale: float) -> void:
	_fire.scale = Vector3.ONE * 0.5 * size_scale
	_fire.show()
	var animation := create_tween()
	animation.tween_method(_advance_atlas, 0.0, float(FRAME_COUNT), fire_seconds)
	animation.parallel().tween_property(_fire, "scale", Vector3.ONE * effect_radius * 0.46, fire_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	animation.tween_callback(_fire.hide)


func _advance_atlas(frame: float) -> void:
	_atlas_material.set_shader_parameter("frame", frame)
