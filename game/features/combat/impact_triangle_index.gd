extends RefCounted
## Local-space BVH: transforms remain live; only immutable mesh faces are indexed.
## Built bottom-up from triangles sorted along a Morton curve (native sort), so a
## 35k-triangle prop indexes in ~0.1 s instead of seconds of GDScript comparisons.
const LEAF_TRIANGLES := 8
const MORTON_BITS := 10
const ID_BITS := 32
var triangles := PackedVector3Array()
var _nodes: Array[Dictionary] = []
var _root := -1


func _init(source: PackedVector3Array) -> void:
	triangles = source
	var count := triangles.size() / 3
	if count > 0:
		_build(_morton_order(count))


func candidates(from: Vector3, to: Vector3) -> PackedInt32Array:
	var result := PackedInt32Array()
	if _root < 0:
		return result
	var pending: Array[int] = [_root]
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


## Triangle numbers ordered along a Morton curve of their centres.
func _morton_order(count: int) -> PackedInt64Array:
	var low := triangles[0]
	var high := triangles[0]
	for vertex in triangles:
		low = low.min(vertex)
		high = high.max(vertex)
	var scale := Vector3.ONE * float((1 << MORTON_BITS) - 1) / (high - low).max(Vector3.ONE * 0.000001)
	var keys := PackedInt64Array()
	keys.resize(count)
	for t in count:
		var cell := ((triangles[t * 3] + triangles[t * 3 + 1] + triangles[t * 3 + 2]) / 3.0 - low) * scale
		var code := _spread(int(cell.x)) | (_spread(int(cell.y)) << 1) | (_spread(int(cell.z)) << 2)
		keys[t] = (code << ID_BITS) | t
	keys.sort()
	return keys


## Leaves of consecutive triangles first, then pairs of neighbours up to a single root.
func _build(keys: PackedInt64Array) -> void:
	var level: Array[int] = []
	var first := 0
	while first < keys.size():
		var ids := PackedInt32Array()
		var bounds := AABB(triangles[(keys[first] & 0xFFFFFFFF) * 3], Vector3.ZERO)
		for k in range(first, mini(first + LEAF_TRIANGLES, keys.size())):
			var offset := int(keys[k] & 0xFFFFFFFF) * 3
			ids.append(offset)
			bounds = bounds.expand(triangles[offset]).expand(triangles[offset + 1]).expand(triangles[offset + 2])
		level.append(_nodes.size())
		_nodes.append({"bounds": bounds.grow(.000001), "ids": ids})
		first += LEAF_TRIANGLES
	while level.size() > 1:
		var parents: Array[int] = []
		for i in range(0, level.size(), 2):
			if i + 1 >= level.size():
				parents.append(level[i])
				continue
			var merged: AABB = (_nodes[level[i]]["bounds"] as AABB).merge(_nodes[level[i + 1]]["bounds"] as AABB)
			parents.append(_nodes.size())
			_nodes.append({"bounds": merged, "left": level[i], "right": level[i + 1]})
		level = parents
	_root = level[0]


## Spaces the low ten bits of `value` two apart, ready to interleave into a Morton code.
static func _spread(value: int) -> int:
	value &= 0x3FF
	value = (value | (value << 16)) & 0x030000FF
	value = (value | (value << 8)) & 0x0300F00F
	value = (value | (value << 4)) & 0x030C30C3
	return (value | (value << 2)) & 0x09249249
