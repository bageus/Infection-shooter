extends RefCounted
## Contact planes in actual model coordinates; no grid/pivot assumptions.
const REACH := 0.45
const WALL_OVERLAP := 0.001

static func is_wall(node: Node3D) -> bool:
	var path := str(node.get_meta("planning_scene_path", node.scene_file_path)).get_file().to_lower()
	if "model_path" in node:
		path = str(node.get("model_path")).get_file().to_lower()
	return path.begins_with("wall_") or path.begins_with("01_wall_") or path.begins_with("01_glass_") or path.begins_with("glass_wall_") or path.begins_with("window_") or path.begins_with("glass_partition_") or path.begins_with("sliding_glass_door")

static func position_for(node: Node3D, bounds: AABB, position: Vector3, neighbors: Array[Dictionary], mounted: bool = false) -> Vector3:
	var source := Transform3D(node.global_basis, position)
	var wall := is_wall(node)
	var best := position
	var distance := REACH
	for record: Dictionary in neighbors:
		var other: Node3D = record["node"]
		var target: Transform3D = other.global_transform
		var box: AABB = record["bounds"]
		if mounted:
			if not bool(other.get_meta("planning_wall_mount", false)) or not other.has_meta("planning_wall_normal"):
				continue
			var normal: Vector3 = node.get_meta("planning_wall_normal")
			if normal.dot(other.get_meta("planning_wall_normal")) < .999 or absf((position - target.origin).dot(normal)) > .03:
				continue
		elif bool(other.get_meta("planning_wall_mount", false)):
			continue
		if wall != is_wall(other):
			continue
		var axes: Array = [0] if wall or mounted else [0, 2]
		for axis in axes:
			for side in [-1.0, 1.0]:
				var normal: Vector3 = source.basis[axis].normalized() * side
				for target_axis in axes:
					var alignment: float = normal.dot(target.basis[target_axis].normalized())
					var perpendicular: bool = wall and absf(alignment) < .001
					if not perpendicular and absf(alignment) < .999:
						continue
					for target_side in [-1.0, 1.0]:
						if not perpendicular and alignment * target_side > -.999:
							continue
						var a := source * _face(bounds, axis, side, not wall)
						var b := target * _face(box, target_axis, target_side, not wall)
						if perpendicular:
							var local := target.affine_inverse() * a
							local.x = clampf(local.x, box.position.x, box.end.x)
							local.z = box.get_center().z
							local.y = box.position.y
							b = target * local
						var shift := b - a
						if mounted:
							if absf(shift.y) > .18:
								continue
						else:
							if absf(shift.y) > .3:
								continue
							if not wall:
								shift.y = 0.0
						if wall:
							var overlap := WALL_OVERLAP
							if perpendicular:
								overlap += box.size.z * target.basis.z.length() * .5
							shift += normal * overlap
						var length := shift.length()
						if length < distance:
							distance = length
							best = position + shift
	return best

static func _face(bounds: AABB, axis: int, side: float, align_back: bool) -> Vector3:
	var point := bounds.get_center()
	point[axis] += bounds.size[axis] * .5 * side
	point.y = bounds.position.y
	if align_back and axis == 0:
		point.z = bounds.position.z # Cabinet backs align even with different depths.
	return point
