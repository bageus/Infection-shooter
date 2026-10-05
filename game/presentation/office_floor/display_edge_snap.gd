extends RefCounted
## Snap screen rectangles within one wall plane; never cross walls or rotations.

static func position(source: Dictionary, neighbors: Array[Dictionary]) -> Vector3:
	var frame: Transform3D = source["frame"]
	var size: Vector2 = source["size"]
	var best := .18
	var correction := Vector3.ZERO
	for neighbor in neighbors:
		var other: Transform3D = neighbor["frame"]
		if frame.basis.x.normalized().dot(other.basis.x.normalized()) < .999 or frame.basis.y.normalized().dot(other.basis.y.normalized()) < .999:
			continue
		var center := frame.affine_inverse() * other.origin
		if absf(center.z) * frame.basis.z.length() > .02:
			continue
		var other_size: Vector2 = neighbor["size"] * Vector2(other.basis.x.length() / frame.basis.x.length(), other.basis.y.length() / frame.basis.y.length())
		var half := (size + other_size) * .5
		for axis in 2:
			var cross_axis := 1 - axis
			if absf(center[cross_axis]) >= half[cross_axis] - .03:
				continue
			var delta := center[axis] - signf(center[axis]) * half[axis]
			var shift := frame.basis.x * delta if axis == 0 else frame.basis.y * delta
			if shift.length() < best:
				best = shift.length()
				correction = shift
	return correction
