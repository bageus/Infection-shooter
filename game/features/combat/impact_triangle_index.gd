extends RefCounted
## Local-space BVH: transforms remain live; only immutable mesh faces are indexed.
const LEAF_TRIANGLES := 8
var triangles := PackedVector3Array()
var _nodes: Array[Dictionary] = []


func _init(source: PackedVector3Array) -> void:
	triangles = source
	var ids: Array[int] = []
	for i in range(0, triangles.size() - 2, 3):
		ids.append(i)
	if not ids.is_empty():
		_build(ids)


func candidates(from: Vector3, to: Vector3) -> PackedInt32Array:
	var result := PackedInt32Array()
	if _nodes.is_empty():
		return result
	var pending: Array[int] = [0]
	while not pending.is_empty():
		var node: Dictionary = _nodes[pending.pop_back()]
		if (node["bounds"] as AABB).intersects_segment(from, to) == null:
			continue
		if node.has("ids"):
			result.append_array(node["ids"])
		else:
			pending.append(node["left"])
			pending.append(node["right"])
	# Preserve the original face order for exactly coincident hits.
	result.sort()
	return result


func _build(ids: Array[int]) -> int:
	var bounds := AABB(triangles[ids[0]], Vector3.ZERO)
	for i in ids:
		bounds = bounds.expand(triangles[i]).expand(triangles[i + 1]).expand(triangles[i + 2])
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
	return (triangles[i][axis] + triangles[i + 1][axis] + triangles[i + 2][axis]) / 3.0
