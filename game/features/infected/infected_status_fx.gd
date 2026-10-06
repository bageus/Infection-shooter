extends Node
## Status presentation on one infected: golden stars circle above the head
## while it is stunned, and the body takes a green tint while it is poisoned.
## The owner reports the status; this node runs only while one is showing.

const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
const POISON_SHADER := preload("res://game/features/infected/poison_tint.gdshader")
const STAR_SIZE := 0.85
const TINT_FADE := 0.4

static var _poison_material: ShaderMaterial

var _body: Node3D
var _visual: Node3D
var _head_height := 1.8
var _stun_left := 0.0
var _poison_left := 0.0
var _stars: MeshInstance3D
var _meshes: Array[MeshInstance3D] = []


func setup(body: Node3D, visual: Node3D, head_height: float) -> void:
	name = "StatusFx"
	_body = body
	_visual = visual
	_head_height = head_height
	set_process(false)


func stunned(seconds: float) -> void:
	_stun_left = maxf(_stun_left, seconds)
	if not is_instance_valid(_stars) and _stun_left > 0.05:
		_stars = FLIPBOOK.spawn(_body, ATLASES.STUN_STARS, _body.global_position + Vector3.UP * _head_height, STAR_SIZE * _visual_scale(), {"cycle": true, "additive": 0.3})
	set_process(true)


func poisoned(seconds: float) -> void:
	if seconds <= 0.0:
		return
	if _poison_left <= 0.0:
		_set_tint(true)
	_poison_left = maxf(_poison_left, seconds)
	set_process(true)


## Death ends both effects; the corpse keeps neither.
func clear() -> void:
	_stun_left = 0.0
	_poison_left = 0.0
	_end_stun()
	_set_tint(false)
	set_process(false)


func is_showing_stun() -> bool:
	return is_instance_valid(_stars)


func is_showing_poison() -> bool:
	return not _meshes.is_empty()


func _process(delta: float) -> void:
	if _stun_left > 0.0:
		_stun_left = maxf(0.0, _stun_left - delta)
		if _stun_left == 0.0:
			_end_stun()
	if _poison_left > 0.0:
		_poison_left = maxf(0.0, _poison_left - delta)
		var fade := clampf(_poison_left / TINT_FADE, 0.0, 1.0)
		for mesh in _meshes:
			if is_instance_valid(mesh):
				mesh.set_instance_shader_parameter(&"fade", fade)
		if _poison_left == 0.0:
			_set_tint(false)
	if _stun_left == 0.0 and _poison_left == 0.0:
		set_process(false)


func _end_stun() -> void:
	if is_instance_valid(_stars):
		_stars.call("stop", 0.2)
	_stars = null


func _set_tint(enabled: bool) -> void:
	if not enabled:
		for mesh in _meshes:
			if is_instance_valid(mesh):
				mesh.material_overlay = null
		_meshes.clear()
		return
	if _visual == null:
		return
	if _poison_material == null:
		_poison_material = ShaderMaterial.new()
		_poison_material.shader = POISON_SHADER
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.visible:
			mesh.material_overlay = _poison_material
			mesh.set_instance_shader_parameter(&"fade", 1.0)
			_meshes.append(mesh)


func _visual_scale() -> float:
	return _visual.scale.x if _visual != null else 1.0
