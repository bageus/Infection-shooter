extends RefCounted
## Versioned authored settings, validated before map replacement.
const KINDS := ["glass", "wall_damage", "wall_scuff", "floor_damage", "floor_scuff", "debris", "bullet"]
const OPACITY := [0.65, 0.7, 0.14, 0.65, 0.18, 1.0, 0.9]

static func normalized(raw: Dictionary) -> Dictionary:
	var result := {}
	for index in KINDS.size():
		var entry: Dictionary = raw.get(KINDS[index], {}) if raw.get(KINDS[index], {}) is Dictionary else {}
		var opacity: Variant = entry.get("opacity", OPACITY[index])
		var size: Variant = entry.get("size", 1.0)
		result[KINDS[index]] = {"opacity": clampf(float(opacity), 0, 1) if _number(opacity) else OPACITY[index],
			"size": clampf(float(size), 0.25, 2) if _number(size) else 1.0}
	return result

static func valid(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	for key: Variant in raw:
		if key not in KINDS or not raw[key] is Dictionary: return false
		for field: Variant in raw[key]:
			if field not in ["opacity", "size"] or not _number(raw[key][field]): return false
			var value := float(raw[key][field])
			if value < (0.0 if field == "opacity" else 0.25) or value > (1.0 if field == "opacity" else 2.0): return false
	return true

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
