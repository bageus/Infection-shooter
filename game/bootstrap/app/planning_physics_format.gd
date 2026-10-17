extends RefCounted
## Validate optional physics payloads before replacing any live map objects.
static func valid(record: Dictionary) -> bool:
	if record.has("settled_physics"):
		var state: Variant = record.settled_physics
		if not state is Dictionary or state.get("version") != 1:
			return false
	var pose: Variant = record.get("decor_pose", {})
	if not pose is Dictionary or not pose.has("physics_v1"):
		return pose is Dictionary
	var data: Variant = pose.physics_v1
	if not data is Dictionary or data.get("version") != 1 or not _transform(data.get("body")):
		return false
	if not data.get("bones") is Dictionary or data.bones.size() > 256:
		return false
	for key: Variant in data.bones:
		if not key is String or key.is_empty() or not _transform(data.bones[key], 0.000000000000001):
			return false
	return true


static func _transform(value: Variant, min_determinant: float = 0.000000001) -> bool:
	if not value is Array or value.size() != 12:
		return false
	for number: Variant in value:
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
	var basis := Basis(Vector3(value[0], value[1], value[2]), Vector3(value[3], value[4], value[5]), Vector3(value[6], value[7], value[8]))
	return absf(basis.determinant()) > min_determinant
