extends RefCounted
## Validate v1 user data before file replacement or scene mutation.
## Keep independent of workstation/zone loaders to avoid a preload cycle.
const MODEL_ROOT := "res://models/objects/enviroments/"


static func valid(data: Variant, desk_type: String) -> bool:
	if not data is Dictionary or desk_type.is_empty():
		return false
	if not _integer(data.get("version")) or data.version != 1 or data.get("desk") != desk_type:
		return false
	if not data.get("zones") is Array or not data.get("items") is Array:
		return false
	if data.has("front") and (not _integer(data.front) or data.front < 0 or data.front > 1):
		return false
	for zone in data.zones:
		if not _zone(zone):
			return false
	for item in data.items:
		if not _item(item, data.zones.size()):
			return false
	return true


static func _zone(zone: Variant) -> bool:
	if not zone is Dictionary:
		return false
	for key in ["x", "z", "width", "depth", "height"]:
		if not _number(zone.get(key)):
			return false
	if zone.width <= 0 or zone.depth <= 0 or not zone.get("floor") is bool:
		return false
	if zone.floor and not is_zero_approx(float(zone.height)):
		return false
	for key in ["name", "category"]:
		if zone.has(key) and not zone[key] is String:
			return false
	if zone.has("required") and not zone.required is bool:
		return false
	if zone.has("angle") and not _number(zone.angle):
		return false
	return true


static func _item(item: Variant, zone_count: int) -> bool:
	if not item is Dictionary or not item.get("path") is String:
		return false
	var path: String = item.path
	if not path.begins_with(MODEL_ROOT) or path != path.simplify_path():
		return false
	if path.get_extension().to_lower() not in ["glb", "gltf", "tscn", "scn"]:
		return false
	if not ResourceLoader.exists(path, "PackedScene"):
		return false
	for key in ["x", "y", "z"]:
		if not _number(item.get(key)):
			return false
	if item.has("yaw") and not _number(item.yaw):
		return false
	for key in ["tilt_x", "tilt_z"]:
		if item.has(key) and not _number(item[key]):
			return false
	# v1 templates without a zone hint still resolve by placement geometry.
	if item.has("zone") and (not _integer(item.zone) or item.zone < -1 or item.zone >= zone_count):
		return false
	return zone_count > 0


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and Vector3(float(value), 0, 0).is_finite()


static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))
