extends RefCounted
## Validate saved map structure before touching the live world.
const NUMBERS := ["x", "y", "z", "rotation_x", "rotation_y", "rotation_z", "scale_x", "scale_y", "scale_z", "zone", "light_energy", "light_angle", "energy_multiplier", "flicker_mode", "flicker_step", "darkness", "spawn_x", "spawn_y", "spawn_z"]


static func error(data: Dictionary) -> String:
	if not data.get("objects") is Array:
		return "objects must be an array"
	if data.has("version"):
		var version: Variant = data.version
		if not _number(version) or float(version) != floorf(float(version)) or float(version) < 1 or float(version) > 8:
			return "unsupported map version"
	for index in data.objects.size():
		var value: Variant = data.objects[index]
		if not value is Dictionary:
			return "object %d must be a dictionary" % index
		var record: Dictionary = value
		if not record.get("scene") is String or not str(record.scene).begins_with("res://"):
			return "object %d has an invalid scene path" % index
		for field: String in NUMBERS:
			if record.has(field) and not _number(record[field]):
				return "object %d has an invalid %s" % [index, field]
		for field: String in ["scale_x", "scale_y", "scale_z"]:
			if record.has(field) and is_zero_approx(float(record[field])):
				return "object %d has zero scale" % index
		for field: String in ["display", "decor_pose", "blood_attachment"]:
			if record.has(field) and not record[field] is Dictionary:
				return "object %d has an invalid %s" % [index, field]
		for field: String in ["display", "decor_pose"]:
			var config: Dictionary = record.get(field, {})
			for number: String in ["seed", "facing"]:
				if config.has(number) and not _number(config[number]):
					return "object %d has an invalid %s.%s" % [index, field, number]
		for field: String in ["light_color", "blood_normal"]:
			if record.has(field) and not _vector(record[field]):
				return "object %d has an invalid %s" % [index, field]
	return ""


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _vector(value: Variant) -> bool:
	return value is Array and value.size() >= 3 and _number(value[0]) and _number(value[1]) and _number(value[2])
