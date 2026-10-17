extends RefCounted
## Versioned JSON-safe skeleton poses, identified by authored bone names.
static func capture(body: Node3D, skeleton: Skeleton3D) -> Dictionary:
	var bones := {}
	for index in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(index)] = encode(skeleton.get_bone_pose(index))
	return {"version": 1, "body": encode(body.transform), "bones": bones}


static func restore(body: Node3D, skeleton: Skeleton3D, data: Dictionary) -> void:
	if data.is_empty():
		return
	body.transform = decode(data.body)
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		if data.bones.has(bone_name):
			skeleton.set_bone_pose(index, decode(data.bones[bone_name]))


static func encode(value: Transform3D) -> Array:
	return [value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z]


static func decode(value: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(value[0], value[1], value[2]),
		Vector3(value[3], value[4], value[5]), Vector3(value[6], value[7], value[8])),
		Vector3(value[9], value[10], value[11]))
