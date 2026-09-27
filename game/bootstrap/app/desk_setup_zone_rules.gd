extends RefCounted

# Move a local placement region and its contents as one transaction.
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")


static func normalize(zone: Dictionary, index: int) -> Dictionary:
	zone["name"] = str(zone.get("name", "Zone %d" % (index + 1)))
	zone["required"] = bool(zone.get("required", true))
	zone["angle"] = float(zone.get("angle", 0.0))
	return zone


static func items_in_zone(desk: Node3D, zone: Dictionary, attached: Array[Node3D]) -> Array[Node3D]:
	var results: Array[Node3D] = []
	for item in attached:
		var local := desk.to_local(item.global_position)
		if absf(local.x - float(zone["x"])) <= float(zone["width"]) * 0.5 and absf(local.z - float(zone["z"])) <= float(zone["depth"]) * 0.5:
			var bounds: AABB = WORKSTATIONS._bounds(item)
			if bool(zone["floor"]) == (bounds.position.y < desk.to_global(Vector3.UP * 0.35).y):
				results.append(item)
	return results


static func rotate_items(desk: Node3D, zone: Dictionary, attached: Array[Node3D], delta_degrees: float) -> void:
	for item in items_in_zone(desk, zone, attached):
		item.rotation.y += deg_to_rad(delta_degrees)


static func overlaps_item(item: Node3D, attached: Array[Node3D]) -> bool:
	var bounds: AABB = WORKSTATIONS._bounds(item)
	var area := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(0.025)
	for other in attached:
		if item == other:
			continue
		var other_bounds: AABB = WORKSTATIONS._bounds(other)
		if other_bounds.position.y < bounds.end.y and other_bounds.end.y > bounds.position.y:
			if area.intersects(Rect2(Vector2(other_bounds.position.x, other_bounds.position.z), Vector2(other_bounds.size.x, other_bounds.size.z))):
				return true
	return false


static func random_items(zone: Dictionary) -> Array[Dictionary]:
	var random := RandomNumberGenerator.new()
	random.randomize()
	var choices := ["05_computer_mouse", "05_desk_phone", "05_laptop_destructible", "05_monitor_destructible", "05_keyboard", "09_notepad", "09_mug", "09_stapler", "11_plant_small"]
	var result: Array[Dictionary] = []
	var count := random.randi_range(1, 3) if bool(zone.get("required", true)) else random.randi_range(0, 2)
	for _i in count:
		result.append({"model": choices[random.randi_range(0, choices.size() - 1)], "x": float(zone["x"]) + random.randf_range(-float(zone["width"]) * 0.33, float(zone["width"]) * 0.33), "z": float(zone["z"]) + random.randf_range(-float(zone["depth"]) * 0.33, float(zone["depth"]) * 0.33)})
	return result


static func move_zone(desk: Node3D, zones: Array[Dictionary], index: int, target: Vector2, stations: Array, attached: Array[Node3D]) -> bool:
	if index < 0 or index >= zones.size():
		return false
	var zone: Dictionary = zones[index]
	var next := Vector2(snappedf(target.x, 0.05), snappedf(target.y, 0.05))
	if not _inside_surface(next, zone, stations):
		return false
	var current := Vector2(float(zone["x"]), float(zone["z"]))
	var movement := next - current
	if movement.length_squared() < 0.0001:
		return false
	var contents := items_in_zone(desk, zone, attached)
	for item in contents:
		item.global_position = desk.to_global(desk.to_local(item.global_position) + Vector3(movement.x, 0, movement.y))
	if _overlaps(contents, attached):
		for item in contents:
			item.global_position = desk.to_global(desk.to_local(item.global_position) - Vector3(movement.x, 0, movement.y))
		return false
	zone["x"] = next.x
	zone["z"] = next.y
	return true


static func _inside_surface(point: Vector2, zone: Dictionary, stations: Array) -> bool:
	var half_width := float(zone["width"]) * 0.5
	var half_depth := float(zone["depth"]) * 0.5
	if bool(zone["floor"]):
		return absf(point.x) + half_width <= 2.75 and absf(point.y) + half_depth <= 2.75
	for station_value in stations:
		var station: Dictionary = station_value
		if absf(point.x - float(station.get("x", 0.0))) + half_width <= 0.95 and absf(point.y - float(station.get("z", 0.0))) + half_depth <= 0.6:
			return true
	return false


static func _overlaps(moved: Array[Node3D], attached: Array[Node3D]) -> bool:
	for item in moved:
		var bounds: AABB = WORKSTATIONS._bounds(item)
		var area := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(0.015)
		for other in attached:
			if item == other:
				continue
			var other_bounds: AABB = WORKSTATIONS._bounds(other)
			if other_bounds.position.y < bounds.end.y and other_bounds.end.y > bounds.position.y:
				if area.intersects(Rect2(Vector2(other_bounds.position.x, other_bounds.position.z), Vector2(other_bounds.size.x, other_bounds.size.z))):
					return true
	return false
