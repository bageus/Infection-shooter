extends Node3D
## Smallest table pieces that came to rest. Each one is drawn as an instance of a
## shared MultiMesh keyed by its mesh, so it keeps its model look. No physics
## bodies and no collision: players walk through and bullets pass. Chunks of
## CHUNK_SIZE are added as needed, so no piece is ever dropped. Presentation only.

const CHUNK_SIZE := 64

var _chunks: Dictionary = {}
var _total := 0


# Bakes the visual of `source` at its current world transform.
func bake(source: MeshInstance3D) -> void:
	if source.mesh == null:
		return
	var key := source.mesh.get_instance_id()
	var list: Array = _chunks.get(key, [])
	if list.is_empty() or (list.back().multimesh as MultiMesh).visible_instance_count >= CHUNK_SIZE:
		list.append(_make_chunk(source))
		_chunks[key] = list
	var multimesh: MultiMesh = (list.back() as MultiMeshInstance3D).multimesh
	var index := multimesh.visible_instance_count
	multimesh.set_instance_transform(index, global_transform.affine_inverse() * source.global_transform)
	multimesh.visible_instance_count = index + 1
	_total += 1


func count() -> int:
	return _total


func _make_chunk(source: MeshInstance3D) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source.mesh
	multimesh.instance_count = CHUNK_SIZE
	multimesh.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = source.material_override
	instance.cast_shadow = source.cast_shadow
	add_child(instance)
	return instance
