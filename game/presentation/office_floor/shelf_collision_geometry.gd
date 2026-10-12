extends RefCounted
## Recover solid boards from flattened shelf and divider meshes without closing their slots.
const PLANE_STEP := 0.002
const MIN_THICKNESS := 0.012


static func applies(path: String) -> bool:
	var file := path.get_file()
	# Office dividers are one flattened mesh too: a single box would close the desk
	# between the walls and leave an invisible lid at panel height.
	if file.begins_with("08_divider_full"):
		return true
	return file.begins_with("03_") and ("book_case" in file or "bookshelf" in file or "with_shelfs" in file)


static func panels(mesh: Mesh) -> Array[AABB]:
	var result: Array[AABB] = []
	for component: PackedVector3Array in _components(mesh.get_faces()):
		var bounds := AABB(component[0], Vector3.ZERO)
		for point in component:
			bounds = bounds.expand(point)
		if maxf(bounds.size.x * bounds.size.y, maxf(bounds.size.x * bounds.size.z, bounds.size.y * bounds.size.z)) < .01:
			continue # Small handles/bevel details are not load-bearing boards.
		# Separate rectangular boards keep their actual full solid thickness.
		if bounds.size[bounds.size.min_axis_index()] <= .09:
			result.append(bounds)
		else:
			result.append_array(_flat_panels(component))
	return _prune(result)


static func _prune(panels: Array[AABB]) -> Array[AABB]:
	for i in panels.size():
		var panel := panels[i]
		for axis in 3:
			if panel.size[axis] < .02:
				panel.position[axis] -= (.02 - panel.size[axis]) * .5
				panel.size[axis] = .02
		panels[i] = panel
	var changed := true
	while changed:
		changed = false
		for i in panels.size():
			for j in range(i + 1, panels.size()):
				if _adjacent(panels[i], panels[j]) or _board_faces(panels[i], panels[j]):
					panels[i] = panels[i].merge(panels[j])
					panels.remove_at(j)
					changed = true
					break
			if changed:
				break
	panels.sort_custom(func(a: AABB, b: AABB) -> bool: return a.get_volume() > b.get_volume())
	var result: Array[AABB] = []
	for panel in panels:
		var covered := false
		for existing in result:
			if existing.grow(.0001).encloses(panel):
				covered = true
				break
		if not covered:
			result.append(panel)
	return result


static func _adjacent(a: AABB, b: AABB) -> bool:
	for axis in 3:
		var aligned := true
		for other in 3:
			if other != axis and (absf(a.position[other] - b.position[other]) > .0002 or absf(a.size[other] - b.size[other]) > .0002):
				aligned = false
		if aligned and a.end[axis] + .0002 >= b.position[axis] and b.end[axis] + .0002 >= a.position[axis]:
			return true
	return false


static func _board_faces(a: AABB, b: AABB) -> bool:
	# Opposite/bevel faces of one board are one collider, not overlapping slabs.
	var axis := a.size.min_axis_index()
	if axis != b.size.min_axis_index() or a.size[axis] > .09 or b.size[axis] > .09:
		return false
	if a.merge(b).size[axis] > .09:
		return false
	var x := (axis + 1) % 3
	var y := (axis + 2) % 3
	var ar := Rect2(Vector2(a.position[x], a.position[y]), Vector2(a.size[x], a.size[y]))
	var br := Rect2(Vector2(b.position[x], b.position[y]), Vector2(b.size[x], b.size[y]))
	# One face must cover the other: adjoining shelves and L-shaped gaps stay apart.
	return ar.grow(.0002).encloses(br) or br.grow(.0002).encloses(ar)


static func _components(faces: PackedVector3Array) -> Array[PackedVector3Array]:
	var parent: Array[int] = []
	var vertices: Dictionary = {}
	for triangle in range(floori(float(faces.size()) / 3.0)):
		parent.append(triangle)
		for corner in 3:
			var point := faces[triangle * 3 + corner] * 100000.0
			var key := Vector3i(roundi(point.x), roundi(point.y), roundi(point.z))
			if vertices.has(key):
				var previous := _root(parent, int(vertices[key]))
				var current := _root(parent, triangle)
				parent[current] = previous
			else:
				vertices[key] = triangle
	var groups: Dictionary = {}
	for triangle in parent.size():
		var key := _root(parent, triangle)
		if not groups.has(key):
			groups[key] = PackedVector3Array()
		for corner in 3:
			groups[key].append(faces[triangle * 3 + corner])
	var result: Array[PackedVector3Array] = []
	for values: PackedVector3Array in groups.values():
		result.append(values)
	return result


static func _root(parent: Array[int], index: int) -> int:
	while parent[index] != index:
		parent[index] = parent[parent[index]]
		index = parent[index]
	return index


static func _flat_panels(faces: PackedVector3Array) -> Array[AABB]:
	var planes: Dictionary = {}
	for offset in range(0, faces.size(), 3):
		var a := faces[offset]
		var b := faces[offset + 1]
		var c := faces[offset + 2]
		var normal := (b - a).cross(c - a).normalized().abs()
		var axis := normal.max_axis_index()
		if normal[axis] < .999:
			continue # Bevels do not define an entire supporting board.
		var key := Vector2i(axis, roundi(a[axis] / PLANE_STEP))
		var bounds := AABB(a, Vector3.ZERO).expand(b).expand(c)
		if not planes.has(key):
			planes[key] = []
		_append_face(planes[key], bounds, axis)
	var result: Array[AABB] = []
	for key: Vector2i in planes:
		for bounds: AABB in planes[key]:
			_append_board(result, bounds, key.x)
	for i in result.size():
		var bounds := result[i]
		for axis in 3:
			if bounds.size[axis] < MIN_THICKNESS:
				bounds.position[axis] -= (MIN_THICKNESS - bounds.size[axis]) * .5
				bounds.size[axis] = MIN_THICKNESS
		result[i] = bounds
	return result


static func _append_face(faces: Array, bounds: AABB, axis: int) -> void:
	var x := (axis + 1) % 3
	var y := (axis + 2) % 3
	var rect := Rect2(Vector2(bounds.position[x], bounds.position[y]), Vector2(bounds.size[x], bounds.size[y]))
	if not rect.has_area():
		return
	for i in faces.size():
		var old: AABB = faces[i]
		var previous := Rect2(Vector2(old.position[x], old.position[y]), Vector2(old.size[x], old.size[y]))
		var union_area := previous.get_area() + rect.get_area() - previous.intersection(rect).get_area()
		# A merge may not bridge the empty space between shelf edges.
		if previous.grow(.0001).intersects(rect) and previous.merge(rect).get_area() <= union_area + .00001:
			faces[i] = old.merge(bounds)
			return
	faces.append(bounds)


static func _append_board(result: Array[AABB], bounds: AABB, axis: int) -> void:
	var size := bounds.size
	if size[(axis + 1) % 3] * size[(axis + 2) % 3] < .01:
		return
	for i in result.size():
		if _same_board(result[i], bounds, axis):
			result[i] = result[i].merge(bounds)
			return
	result.append(bounds)


static func _same_board(a: AABB, b: AABB, axis: int) -> bool:
	for other in 3:
		if other != axis and (absf(a.position[other] - b.position[other]) > .008 or absf(a.size[other] - b.size[other]) > .016):
			return false
	return absf(a.get_center()[axis] - b.get_center()[axis]) < .08 and a.size[axis] < .08
