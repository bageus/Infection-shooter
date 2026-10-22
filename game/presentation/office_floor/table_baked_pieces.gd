extends Node3D
## Smallest table pieces that came to rest. Each one is drawn as an instance of a
## shared MultiMesh keyed by its mesh, so it keeps its model look. No physics
## bodies and no collision: players walk through and bullets pass. Chunks of
## CHUNK_SIZE are added as needed, so no piece is ever dropped. Presentation only.

const CHUNK_SIZE := 64
# Each chunk keeps a CPU copy of its transforms: a MultiMesh cannot be read back on every renderer.
const TRANSFORMS_META := &"baked_transforms"

var _chunks: Dictionary = {}
var _total := 0


# Bakes the visual of `source` at its current world transform, moved down by `drop` metres.
func bake(source: MeshInstance3D, drop: float = 0.0) -> void:
	if source.mesh == null:
		return
	var key := source.mesh.get_instance_id()
	var list: Array = _chunks.get(key, [])
	if list.is_empty() or (list.back().multimesh as MultiMesh).visible_instance_count >= CHUNK_SIZE:
		list.append(_make_chunk(source))
		_chunks[key] = list
	var multimesh: MultiMesh = (list.back() as MultiMeshInstance3D).multimesh
	var index := multimesh.visible_instance_count
	var local := global_transform.affine_inverse() * Transform3D(source.global_basis, source.global_position - Vector3(0.0, drop, 0.0))
	multimesh.set_instance_transform(index, local)
	(list.back() as MultiMeshInstance3D).get_meta(TRANSFORMS_META).append(local)
	multimesh.visible_instance_count = index + 1
	_total += 1


func count() -> int:
	return _total


# Removes the baked pieces within `radius` (floor plane) of `point`, nearest chunks first, up to `limit`.
# Each record carries what a loose body needs: mesh, material, shadow mode and world transform.
func release_near(point: Vector3, radius: float, limit: int) -> Array[Dictionary]:
	var released: Array[Dictionary] = []
	var flat := Vector2(point.x, point.z)
	for list: Array in _chunks.values():
		for chunk: MultiMeshInstance3D in list:
			var multimesh := chunk.multimesh
			var transforms: Array = chunk.get_meta(TRANSFORMS_META)
			var index := transforms.size() - 1
			while index >= 0 and released.size() < limit:
				var world := global_transform * (transforms[index] as Transform3D)
				if Vector2(world.origin.x, world.origin.z).distance_to(flat) <= radius:
					released.append({"mesh": multimesh.mesh, "material": chunk.material_override, "shadow": chunk.cast_shadow, "transform": world})
					var last := transforms.size() - 1
					if index != last:
						transforms[index] = transforms[last]
						multimesh.set_instance_transform(index, transforms[index])
					transforms.pop_back()
					multimesh.visible_instance_count = last
					_total -= 1
				index -= 1
			if released.size() >= limit:
				return released
	return released


func _make_chunk(source: MeshInstance3D) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source.mesh
	multimesh.instance_count = CHUNK_SIZE
	multimesh.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.set_meta(TRANSFORMS_META, [])
	instance.material_override = source.material_override
	instance.cast_shadow = source.cast_shadow
	add_child(instance)
	return instance
