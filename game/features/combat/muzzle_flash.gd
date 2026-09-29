extends Node3D

const FRAMES := 6

@export_range(0.06, 0.4, 0.01) var duration := 0.19
@export_range(0.1, 1.4, 0.01) var width := 0.425
@export_range(0.1, 1.0, 0.01) var height := 0.26
@export_range(0.0, 1.0, 0.01) var tip_position := 0.20

@onready var _visual: MeshInstance3D = $Visual

var _elapsed := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	_material = (_visual.mesh.surface_get_material(0) as ShaderMaterial).duplicate() as ShaderMaterial
	_visual.material_override = _material
	_visual.scale = Vector3(width, height, 1.0)
	_material.set_shader_parameter("frame_index", 0)
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	_material.set_shader_parameter("frame_index", mini(int(_elapsed / duration * FRAMES), FRAMES - 1))
	var nozzle := get_parent() as Node3D
	var camera := get_viewport().get_camera_3d()
	if nozzle == null or camera == null:
		return
	var toward_camera := camera.global_position - nozzle.global_position
	if toward_camera.length_squared() < 0.0001:
		return
	toward_camera = toward_camera.normalized()
	var fire_direction := -nozzle.global_basis.z.normalized()
	var right := fire_direction - toward_camera * fire_direction.dot(toward_camera)
	if right.length_squared() < 0.001:
		right = camera.global_basis.x
	right = right.normalized()
	var up := toward_camera.cross(right).normalized()
	_visual.global_basis = Basis(right, up, toward_camera).scaled(Vector3(width, height, 1.0))
	_visual.global_position = nozzle.global_position + right * width * (0.5 - tip_position)
