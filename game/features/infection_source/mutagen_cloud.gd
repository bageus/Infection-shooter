extends Area3D

const WALL_FIELD := preload("res://game/features/infection_source/cloud_wall_field.gd")

signal depleted

@export var absorption_seconds: float = 2.0
@export var lifetime_seconds: float = 14.0
@export var permanent: bool = false

var _active: bool = false
var _absorption_remaining: float = 0.0
var _lifetime_remaining: float = 0.0
var _cycle_elapsed: float = 0.0
@onready var _visual: MeshInstance3D = $Visual


func _ready() -> void:
	monitoring = false
	visible = false


func activate() -> void:
	_active = true
	_absorption_remaining = absorption_seconds
	_lifetime_remaining = lifetime_seconds
	_cycle_elapsed = 0.0
	_visual.set_instance_shader_parameter("phase", randf_range(0.0, 100.0))
	_visual.set_instance_shader_parameter("progress", 0.0)
	var shared_material := _visual.mesh.surface_get_material(0) as ShaderMaterial
	if shared_material != null:
		var cloud_material := shared_material.duplicate() as ShaderMaterial
		cloud_material.set_shader_parameter("wall_mask", WALL_FIELD.texture_for(self))
		cloud_material.set_shader_parameter("wall_mask_enabled", true)
		_visual.material_override = cloud_material
	monitoring = true
	visible = true


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if permanent:
		_cycle_elapsed = fposmod(_cycle_elapsed + delta, maxf(lifetime_seconds, 0.001))
		_visual.set_instance_shader_parameter("progress", _cycle_elapsed / maxf(lifetime_seconds, 0.001))
		var visitor := _find_absorbing_body()
		if visitor != null:
			visitor.call("absorb_mutagen", delta)
		return

	_lifetime_remaining -= delta
	_visual.set_instance_shader_parameter("progress", 1.0 - clampf(_lifetime_remaining / maxf(lifetime_seconds, 0.001), 0.0, 1.0))
	if _lifetime_remaining <= 0.0:
		_finish()
		return

	if _absorption_remaining <= 0.0:
		# The mutagen is spent, but the visual cloud finishes dissipating naturally.
		return

	var absorbing_body: Node = _find_absorbing_body()
	if absorbing_body == null:
		return

	var step := minf(delta, _absorption_remaining)
	absorbing_body.call("absorb_mutagen", step)
	_absorption_remaining -= step
	if _absorption_remaining <= 0.0:
		monitoring = false


func _find_absorbing_body() -> Node:
	for body in get_overlapping_bodies():
		if body != null and body.has_method("absorb_mutagen") and WALL_FIELD.clear_to(self, body):
			return body
	return null


func _finish() -> void:
	if not _active:
		return
	_active = false
	monitoring = false
	visible = false
	depleted.emit()
