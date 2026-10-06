extends RefCounted

# Connected edge neighbors on the same screen plane; no SceneTree queries.
const EDGE_TOLERANCE := .025
const PLANE_TOLERANCE := .012


func apply(displays: Array) -> void:
	var pending: Array = []
	for display: Node3D in displays:
		if display.get("tiled") and not display.get("damaged") and not display.get("prop").get_meta("planning_preview", false):
			pending.append(display)
	while not pending.is_empty():
		var first: Node3D = pending.pop_front()
		var frame: Transform3D = first.call("wall_frame")
		var group: Array[Node3D] = [first]
		var bounds: Array[Rect2] = [_bounds(first, frame)]
		_collect(pending, group, bounds, frame)
		var combined := bounds[0]
		for rectangle: Rect2 in bounds:
			combined = combined.merge(rectangle)
		# Lowest authored seed keeps the choice independent of registration order.
		var lowest_seed := int(first.get("config").get("seed", 1))
		for display in group:
			lowest_seed = mini(lowest_seed, int(display.get("config").get("seed", 1)))
		for i in range(group.size()):
			var rectangle := bounds[i]
			var origin := (rectangle.position - combined.position) / combined.size
			var size := rectangle.size / combined.size
			# Screen UV origin is at the top left; geometric bounds grow upward.
			origin.y = 1.0 - origin.y - size.y
			group[i].call("set_wall_content", lowest_seed % 3, Rect2(origin, size))


func _collect(pending: Array, group: Array[Node3D], bounds: Array[Rect2], frame: Transform3D) -> void:
	var cursor := 0
	while cursor < group.size():
		for i in range(pending.size() - 1, -1, -1):
			var candidate := pending[i] as Node3D
			if not _coplanar(frame, candidate.call("wall_frame")):
				continue
			var rectangle := _bounds(candidate, frame)
			if _adjacent(bounds[cursor], rectangle):
				group.append(candidate)
				bounds.append(rectangle)
				pending.remove_at(i)
		cursor += 1


func _coplanar(a: Transform3D, b: Transform3D) -> bool:
	if a.basis.x.normalized().dot(b.basis.x.normalized()) < .999 or a.basis.y.normalized().dot(b.basis.y.normalized()) < .999:
		return false
	if absf(a.basis.z.normalized().dot(b.origin - a.origin)) > PLANE_TOLERANCE:
		return false
	return a.basis.get_scale().is_equal_approx(b.basis.get_scale())


func _bounds(display: Node3D, anchor: Transform3D) -> Rect2:
	var frame: Transform3D = display.call("wall_frame")
	var center := anchor.affine_inverse() * frame.origin
	var profile: Dictionary = (display.get("screens") as Array)[0]["profile"]
	var size := Vector2(float(profile["size"][0]), float(profile["size"][1]))
	return Rect2(Vector2(center.x, center.y) - size / 2.0, size)


func _adjacent(a: Rect2, b: Rect2) -> bool:
	var shared_y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	var shared_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var horizontal := minf(absf(a.end.x - b.position.x), absf(b.end.x - a.position.x)) <= EDGE_TOLERANCE and shared_y > .05
	var vertical := minf(absf(a.end.y - b.position.y), absf(b.end.y - a.position.y)) <= EDGE_TOLERANCE and shared_x > .05
	return horizontal or vertical
