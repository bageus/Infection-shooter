extends Node3D
## One MultiMesh holding debris pieces that have come to rest and been left alone.
## Presentation only: settled pieces draw as one batch, have no collision and
## cannot be hit or kicked any more.

const CAPACITY := 256

var _multimesh: MultiMesh
var _count := 0


func _ready() -> void:
	var cube := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	material.vertex_color_use_as_albedo = true
	cube.material = material
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = cube
	_multimesh.instance_count = CAPACITY
	_multimesh.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.name = "SettledPieces"
	instance.multimesh = _multimesh
	add_child(instance)


# Returns false when the batch is full; the caller keeps the piece as it was.
func add(piece_transform: Transform3D, tint: Color) -> bool:
	if _count >= CAPACITY:
		return false
	_multimesh.set_instance_transform(_count, piece_transform)
	_multimesh.set_instance_color(_count, tint)
	_count += 1
	_multimesh.visible_instance_count = _count
	return true


func count() -> int:
	return _count
