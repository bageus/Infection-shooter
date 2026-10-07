extends RefCounted
## Immutable surface topology; volume queries preserve source triangle order.
const LEAF_TRIANGLES := 8
var _triangles := PackedVector3Array()
var _nodes: Array[Dictionary] = []


func _init(arrays: Array) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	var ids: Array[int] = []
	for i in range(0, count - 2, 3):
		ids.append(i)
		for k in 3:
			_triangles.append(vertices[indices[i + k] if not indices.is_empty() else i + k])
	if not ids.is_empty():
		_build(ids)


func candidates(volume: AABB) -> PackedInt32Array:
	var result := PackedInt32Array()
	if _nodes.is_empty():
		return result
	var pending: Array[int] = [0]
	while not pending.is_empty():
		var node: Dictionary = _nodes[pending.pop_back()]
		if not (node["bounds"] as AABB).intersects(volume):
			continue
		if node.has("ids"):
			result.append_array(node["ids"])
		else:
			pending.append(node["left"])
			pending.append(node["right"])
	result.sort()
	return result


func _build(ids: Array[int]) -> int:
	var bounds := AABB(_triangles[ids[0]], Vector3.ZERO)
	for i in ids:
		bounds = bounds.expand(_triangles[i]).expand(_triangles[i + 1]).expand(_triangles[i + 2])
	var index := _nodes.size()
	_nodes.append({"bounds": bounds.grow(.000001)})
	if ids.size() <= LEAF_TRIANGLES:
		_nodes[index]["ids"] = PackedInt32Array(ids)
		return index
	var axis := bounds.get_longest_axis_index()
	ids.sort_custom(func(a: int, b: int) -> bool:
		return _center(a, axis) < _center(b, axis))
	var middle := int(ids.size() / 2.0)
	_nodes[index]["left"] = _build(ids.slice(0, middle))
	_nodes[index]["right"] = _build(ids.slice(middle))
	return index


func _center(i: int, axis: int) -> float:
	return (_triangles[i][axis] + _triangles[i + 1][axis] + _triangles[i + 2][axis]) / 3.0
