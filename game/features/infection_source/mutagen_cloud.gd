extends Area3D

const WALL_FIELD := preload("res://game/features/infection_source/cloud_wall_field.gd")
const CLOUD_SHADER := preload("res://game/features/infection_source/mutagen_cloud.gdshader")
const ATLAS_A := preload("res://models/objects/textures/mutagen/Six Emerald Gas Cloud Sprites-2.png")
const ATLAS_B := preload("res://models/objects/textures/mutagen/Six-Frame Toxic Gas Cloud Atlas-1.png")
const EMERALD := Color(0.86, 1.06, 0.84)
const TOXIC := Color(1.08, 1.1, 0.68)

signal depleted

@export var absorption_seconds: float = 2.0
@export var lifetime_seconds: float = 14.0
@export var permanent: bool = false
## A fresh death cloud waits this long before it starts feeding mutagen, so
## the player can step out of it.
@export var absorb_delay: float = 0.6
## Gas puffs per cloud (random in range) and how far they spread from the centre.
@export var puff_count_range := Vector2i(7, 10)
@export var cloud_radius := 1.35

var _active: bool = false
var _absorption_remaining: float = 0.0
var _lifetime_remaining: float = 0.0
var _cycle_elapsed: float = 0.0
var _delay_remaining: float = 0.0
# Variant, seed, spin and stagger of every puff (what the MultiMesh holds).
var _puffs: Array[Color] = []
@onready var _visual: MultiMeshInstance3D = $Visual
@onready var _haze: MultiMeshInstance3D = $GroundHaze
@onready var _spores: GPUParticles3D = $Spores


func _ready() -> void:
	monitoring = false
	visible = false


func activate() -> void:
	_active = true
	_absorption_remaining = absorption_seconds
	_lifetime_remaining = lifetime_seconds
	_cycle_elapsed = 0.0
	_delay_remaining = 0.0 if permanent else absorb_delay
	var walls := WALL_FIELD.texture_for(self)
	var phase := randf_range(0.0, 100.0)
	# Every cloud is new: its own puffs, variants, layout, spin and shade.
	var shade := randf()
	_visual.multimesh = _build_puffs(randi_range(puff_count_range.x, puff_count_range.y), shade)
	_visual.material_override = _cloud_material(walls, false)
	_haze.multimesh = _build_haze(shade)
	_haze.material_override = _cloud_material(walls, true)
	for layer in [_visual, _haze]:
		layer.set_instance_shader_parameter("phase", phase)
		layer.set_instance_shader_parameter("progress", 0.0)
		layer.set_instance_shader_parameter("looping", 1.0 if permanent else 0.0)
		layer.set_instance_shader_parameter("cycle_seconds", maxf(lifetime_seconds, 1.0))
		layer.set_instance_shader_parameter("cloud_center", global_position)
	_spores.restart()
	_spores.emitting = true
	monitoring = true
	visible = true


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if permanent:
		_cycle_elapsed = fposmod(_cycle_elapsed + delta, maxf(lifetime_seconds, 0.001))
		_set_progress(_cycle_elapsed / maxf(lifetime_seconds, 0.001))
		var visitor := _find_absorbing_body()
		if visitor != null:
			visitor.call("absorb_mutagen", delta)
		return

	_lifetime_remaining -= delta
	_set_progress(1.0 - clampf(_lifetime_remaining / maxf(lifetime_seconds, 0.001), 0.0, 1.0))
	if _lifetime_remaining <= 0.0:
		_finish()
		return

	if _absorption_remaining <= 0.0:
		# The mutagen is spent, but the visual cloud finishes dissipating naturally.
		return
	if _delay_remaining > 0.0:
		_delay_remaining -= delta
		return

	var absorbing_body: Node = _find_absorbing_body()
	if absorbing_body == null:
		return

	var step := minf(delta, _absorption_remaining)
	absorbing_body.call("absorb_mutagen", step)
	_absorption_remaining -= step
	if _absorption_remaining <= 0.0:
		monitoring = false


# Overlapping clouds do not stack: a body absorbs from one cloud per frame.
func _find_absorbing_body() -> Node:
	var frame := Engine.get_physics_frames()
	for body in get_overlapping_bodies():
		if body == null or not body.has_method("absorb_mutagen"):
			continue
		if int(body.get_meta(&"mutagen_absorbed_frame", -1)) == frame:
			continue
		if WALL_FIELD.clear_to(self, body):
			body.set_meta(&"mutagen_absorbed_frame", frame)
			return body
	return null


func _set_progress(value: float) -> void:
	_visual.set_instance_shader_parameter("progress", value)
	_haze.set_instance_shader_parameter("progress", value)
	if not permanent and value > 0.55:
		_spores.emitting = false


# Puffs: big ones low in the core, smaller ones higher and further out.
func _build_puffs(count: int, shade: float) -> MultiMesh:
	var multimesh := _multimesh(count)
	var variants := range(12)
	variants.shuffle()
	var stagger := range(count)
	stagger.shuffle()
	_puffs.clear()
	for i in count:
		var reach := sqrt(randf()) * cloud_radius
		var angle := randf() * TAU
		var height := lerpf(0.75, 2.05, randf() * 0.5 + reach / cloud_radius * 0.5)
		var size := lerpf(2.9, 1.7, reach / cloud_radius) * randf_range(0.85, 1.1)
		var origin := Vector3(cos(angle) * reach, height, sin(angle) * reach)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), origin))
		var spin := randf_range(0.05, 0.22) * (1.0 if randf() < 0.5 else -1.0)
		var data := Color(float(variants[i % 12]) / 12.0, randf(), spin, float(stagger[i]) / float(count))
		multimesh.set_instance_custom_data(i, data)
		_puffs.append(data)
		var tint := EMERALD.lerp(TOXIC, clampf(shade + randf_range(-0.3, 0.3), 0.0, 1.0))
		multimesh.set_instance_color(i, Color(tint, randf_range(0.82, 1.0)))
	return multimesh


# A wide, faint layer of gas creeping over the floor under the cloud.
func _build_haze(shade: float) -> MultiMesh:
	var multimesh := _multimesh(1)
	multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * cloud_radius * 3.4), Vector3(0, 0.06, 0)))
	multimesh.set_instance_custom_data(0, Color(float(randi() % 12) / 12.0, randf(), randf_range(-0.06, 0.06), 0.0))
	multimesh.set_instance_color(0, Color(EMERALD.lerp(TOXIC, shade) * 0.8, 0.5))
	return multimesh


func _multimesh(count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	multimesh.instance_count = count
	return multimesh


func _cloud_material(walls: Texture2D, ground: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	material.set_shader_parameter("atlas_a", ATLAS_A)
	material.set_shader_parameter("atlas_b", ATLAS_B)
	material.set_shader_parameter("wall_mask", walls)
	material.set_shader_parameter("wall_mask_enabled", true)
	material.set_shader_parameter("wall_radius", WALL_FIELD.RADIUS)
	material.set_shader_parameter("ground", ground)
	if ground:
		material.set_shader_parameter("vein_glow", 0.6)
		material.set_shader_parameter("flow_speed", 0.2)
	return material


func _finish() -> void:
	if not _active:
		return
	_active = false
	monitoring = false
	visible = false
	_spores.emitting = false
	depleted.emit()
