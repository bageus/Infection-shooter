extends Area3D

const WALL_FIELD := preload("res://game/features/infection_source/cloud_wall_field.gd")
const CLOUD_SHADER := preload("res://game/features/infection_source/mutagen_cloud.gdshader")
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
@export var puff_count_range := Vector2i(3, 4)
@export var cloud_radius := 1.35
## Legacy visitor fallback; players own Devourer via on_mutagen_cloud().
@export var heals_visitors := false
## False: no time limit, so the cloud lasts until it is absorbed (needs ends_when_absorbed).
@export var timed := true
## The cloud ends once it has given absorb_units of mutagen, rather than after its feed budget.
@export var ends_when_absorbed := false
@export var absorb_units := 10.0
const HEAL_PER_SECOND := 2.0

var _floor_offset := 0.0
var _active: bool = false
var _absorption_remaining: float = 0.0
var _lifetime_remaining: float = 0.0
var _cycle_elapsed: float = 0.0
var _delay_remaining: float = 0.0
var _absorbed_units: float = 0.0
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
	# An absorption-ended cloud feeds until its mutagen threshold; INF keeps the budget open.
	_absorption_remaining = INF if ends_when_absorbed else absorption_seconds
	_absorbed_units = 0.0
	# An untimed cloud has no end; INF keeps its progress at the fresh end.
	_lifetime_remaining = lifetime_seconds if timed else INF
	_cycle_elapsed = 0.0
	_delay_remaining = 0.0 if permanent else absorb_delay
	_floor_offset = _support_height() - global_position.y
	($CollisionShape3D as CollisionShape3D).position.y = _floor_offset + 1.25
	var walls := WALL_FIELD.texture_for(self)
	var phase := randf_range(0.0, 100.0)
	# Every cloud is new: its own puffs, variants, layout, spin and shade.
	var shade := randf()
	_visual.multimesh = _build_puffs(randi_range(puff_count_range.x, puff_count_range.y), shade)
	_visual.material_override = _cloud_material(walls, false)
	_haze.multimesh = _build_haze(shade)
	_haze.material_override = _cloud_material(walls, false)
	(_haze.material_override as ShaderMaterial).set_shader_parameter("opacity", .18)
	(_haze.material_override as ShaderMaterial).set_shader_parameter("flow_speed", .2)
	# Plain material parameters: each cloud owns its materials, and an instance
	# uniform would take 16 of the renderer's 4096 slots (256 objects) per layer.
	for layer in [_visual, _haze]:
		var material := layer.material_override as ShaderMaterial
		material.set_shader_parameter("phase", phase)
		material.set_shader_parameter("progress", 0.0)
		material.set_shader_parameter("looping", 1.0 if permanent else 0.0)
		material.set_shader_parameter("cycle_seconds", maxf(lifetime_seconds, 1.0))
		material.set_shader_parameter("cloud_center", global_position + Vector3.UP * _floor_offset)
	_spores.emitting = false
	monitoring = true
	visible = true
	if not permanent:
		_register_death_cloud()


func _support_height() -> float:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * .1, global_position - Vector3.UP * 6.0, 3)
	var excluded: Array[RID] = []
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is CollisionObject3D:
			excluded.append((ancestor as CollisionObject3D).get_rid())
		ancestor = ancestor.get_parent()
	query.exclude = excluded
	for _attempt in 16:
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Node = hit["collider"]
		if collider is CharacterBody3D or (collider is RigidBody3D and not (collider as RigidBody3D).freeze):
			excluded.append(hit["rid"])
			query.exclude = excluded
			continue
		return (hit["position"] as Vector3).y
	return global_position.y


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if permanent:
		_heal_visitors(delta)
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

	_heal_visitors(delta)
	if _absorption_remaining <= 0.0:
		# The mutagen is spent, but the visual cloud finishes dissipating naturally.
		return
	if _delay_remaining > 0.0:
		_delay_remaining -= delta
		return

	var absorbing_body: Node = _find_absorbing_body()
	if absorbing_body == null:
		return

	_feed(absorbing_body, minf(delta, _absorption_remaining))


# The cloud only spends what the body actually takes: while the player has
# lost control the infection refuses mutagen, and the cloud keeps it.
func _feed(body: Node, step: float) -> void:
	var gained: Variant = body.call("absorb_mutagen", step)
	if gained is float and float(gained) <= 0.0:
		return
	_absorption_remaining -= step
	if gained is float and ends_when_absorbed:
		_absorbed_units += float(gained)
		if _absorbed_units >= absorb_units:
			_dissipate_early()
	# Keep detecting presence until dissipation: a visitor may have Devourer
	# even when this cloud was created before that skill became active.


# Cloud presence is delivered once per body/physics frame, even when mutagen
# is spent or refused. The player decides whether Devourer is currently active.
func _heal_visitors(delta: float) -> void:
	var frame := Engine.get_physics_frames()
	for body in get_overlapping_bodies():
		if body == null or not body.has_method("absorb_mutagen"):
			continue
		if not body.has_method("on_mutagen_cloud") and not heals_visitors:
			continue
		if int(body.get_meta(&"mutagen_presence_frame", -1)) == frame or not WALL_FIELD.clear_to(self, body):
			continue
		body.set_meta(&"mutagen_presence_frame", frame)
		if body.has_method("on_mutagen_cloud"):
			body.call("on_mutagen_cloud", delta)
		elif body.has_method("heal"):
			body.call("heal", HEAL_PER_SECOND * delta)


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
	(_visual.material_override as ShaderMaterial).set_shader_parameter("progress", value)
	(_haze.material_override as ShaderMaterial).set_shader_parameter("progress", value)
	if not permanent and value > 0.55:
		_spores.emitting = false


# Puffs: a big one low in the core, smaller ones higher and further out.
# Each carries an independent noise seed and flow phase.
func _build_puffs(count: int, shade: float) -> MultiMesh:
	var multimesh := _multimesh(count)
	var variants := range(12)
	variants.shuffle()
	var stagger := range(count)
	stagger.shuffle()
	_puffs.clear()
	var ring_turn := randf() * TAU
	for i in count:
		# One puff holds the core; the rest ring it evenly so no side is bare.
		var reach := randf_range(0.0, 0.25) * cloud_radius if i == 0 else randf_range(0.55, 0.95) * cloud_radius
		var angle := float(i) * TAU / float(maxi(count - 1, 1)) + ring_turn + randf_range(-0.35, 0.35)
		var height := lerpf(0.9, 1.45, randf() * 0.5 + reach / cloud_radius * 0.5)
		var size := lerpf(3.3, 2.1, reach / cloud_radius) * randf_range(0.9, 1.1)
		var origin := Vector3(cos(angle) * reach, height + _floor_offset, sin(angle) * reach)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), origin))
		var spin := randf_range(0.05, 0.22) * (1.0 if randf() < 0.5 else -1.0)
		var data := Color(float(variants[i % 12]) / 12.0, randf(), spin, float(stagger[i]) / float(count))
		multimesh.set_instance_custom_data(i, data)
		_puffs.append(data)
		var tint := EMERALD.lerp(TOXIC, clampf(shade + randf_range(-0.3, 0.3), 0.0, 1.0))
		multimesh.set_instance_color(i, Color(tint, randf_range(0.82, 1.0)))
	return multimesh


# Faint low billboards mix into the cloud; no flat floor image/reflection.
func _build_haze(shade: float) -> MultiMesh:
	var multimesh := _multimesh(1)
	for i in range(1):
		var angle := float(i) * TAU / 3.0 + randf_range(-.3, .3)
		var origin := Vector3(cos(angle) * .45, randf_range(.65, .85) + _floor_offset, sin(angle) * .45)
		var size := randf_range(.9, 1.3)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), origin))
		multimesh.set_instance_custom_data(i, Color(float(randi() % 12) / 12.0, randf(), randf_range(-.03, .03), .1 * i))
		multimesh.set_instance_color(i, Color(EMERALD.lerp(TOXIC, shade) * .8, .5))
	return multimesh


static var _quad: QuadMesh
# Death clouds alive at once; past the cap the oldest dissipates early.
const MAX_DEATH_CLOUDS := 10
static var _death_clouds: Array[WeakRef] = []


func _register_death_cloud() -> void:
	var alive: Array[WeakRef] = []
	for ref in _death_clouds:
		var cloud := ref.get_ref() as Node
		if cloud != null and bool(cloud.get("_active")):
			alive.append(ref)
	alive.append(weakref(self))
	while alive.size() > MAX_DEATH_CLOUDS:
		var oldest := alive.pop_front().get_ref() as Node
		if oldest != null:
			oldest.call("_dissipate_early")
	_death_clouds = alive


## Jumps to the dissolving part of the cloud's life (no new absorption).
func _dissipate_early() -> void:
	_absorption_remaining = 0.0
	_lifetime_remaining = minf(_lifetime_remaining, lifetime_seconds * 0.25)


func _multimesh(count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	multimesh.mesh = _quad
	multimesh.instance_count = count
	return multimesh


func _cloud_material(walls: Texture2D, ground: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	material.set_shader_parameter("wall_mask", walls)
	material.set_shader_parameter("wall_mask_enabled", true)
	material.set_shader_parameter("wall_radius", WALL_FIELD.RADIUS)
	material.set_shader_parameter("ground", ground)
	if ground:
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
