extends RefCounted

# Move a local placement region and its contents as one transaction.
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const GEOMETRY := preload("res://game/bootstrap/app/desk_setup_zone_geometry.gd")
const CATEGORIES := ["Монитор", "Клавиатура", "Мышь", "Ноутбук", "Стакан", "Кружка", "Карандаш", "Ручка", "Бумага", "Книги", "Mini PC", "Tower PC", "Другие", "Кресло"]


static func category_for(model: String) -> String:
	var label := model.to_lower()
	if "chair" in label: return "Кресло"
	if "monitor" in label: return "Монитор"
	if "keyboard" in label: return "Клавиатура"
	if "laptop" in label: return "Ноутбук"
	if "mouse" in label: return "Мышь"
	if "minipc" in label: return "Mini PC"
	if "computer_tower" in label or label.begins_with("05_pc_"): return "Tower PC"
	if "mug" in label: return "Кружка"
	if label.begins_with("09_glass"): return "Стакан"
	if "pencil" in label: return "Карандаш"
	if label.begins_with("09_pen_"): return "Ручка"
	if "book" in label: return "Книги"
	if "paper" in label or "file" in label or "notepad" in label or "binder" in label: return "Бумага"
	return "Другие"


static func models_for(category: String) -> Array[String]:
	var choices: Array[String] = []
	for model in WORKSTATIONS.available_models():
		if category_for(model) == category:
			choices.append(model)
	return choices


static func normalize(zone: Dictionary, index: int) -> Dictionary:
	zone["name"] = str(zone.get("name", "Zone %d" % (index + 1)))
	zone["required"] = bool(zone.get("required", true))
	zone["angle"] = float(zone.get("angle", 0.0))
	var old_category := str(zone.get("category", "Другие"))
	var aliases := {"Any": "Другие", "Other": "Другие", "Chair": "Кресло", "Monitor": "Монитор", "Keyboard": "Клавиатура", "Laptop": "Ноутбук", "Computer": "Tower PC", "Mouse": "Мышь", "Drinkware": "Стакан", "Paper": "Бумага", "Book": "Книги"}
	zone["category"] = aliases.get(old_category, old_category) if aliases.get(old_category, old_category) in CATEGORIES else "Другие"
	return zone


static func items_in_zone(desk: Node3D, zone: Dictionary, attached: Array[Node3D]) -> Array[Node3D]:
	var results: Array[Node3D] = []
	for item in attached:
		if item.has_meta("planning_zone") and int(zone.get("slot", -1)) >= 0:
			if int(item.get_meta("planning_zone")) == int(zone["slot"]):
				results.append(item)
			continue
		var local := desk.to_local(item.global_position)
		var delta := Vector3(local.x - float(zone["x"]), 0, local.z - float(zone["z"])).rotated(Vector3.UP, -deg_to_rad(float(zone.get("angle", 0.0))))
		if absf(delta.x) <= float(zone["width"]) * 0.5 and absf(delta.z) <= float(zone["depth"]) * 0.5:
			var bounds: AABB = WORKSTATIONS._bounds(item)
			if bool(zone["floor"]) == (bounds.position.y < desk.to_global(Vector3.UP * 0.35).y):
				results.append(item)
	return results


static func fits_zone(desk: Node3D, zone: Dictionary, item: Node3D) -> bool:
	return GEOMETRY.fits_zone(desk, zone, item)


static func rotate_items(desk: Node3D, zone: Dictionary, attached: Array[Node3D], delta_degrees: float) -> bool:
	var moved := items_in_zone(desk, zone, attached)
	var pivot := Vector3(float(zone["x"]), 0, float(zone["z"]))
	var proposed := zone.duplicate()
	proposed["angle"] = float(zone.get("angle", 0.0)) + delta_degrees
	for item in moved:
		item.global_position = desk.to_global((desk.to_local(item.global_position) - pivot).rotated(Vector3.UP, deg_to_rad(delta_degrees)) + pivot)
		item.rotation.y += deg_to_rad(delta_degrees)
	var outside := false
	for item in moved:
		if not fits_zone(desk, proposed, item):
			outside = true
			break
	if outside or _overlaps(moved, attached):
		for item in moved:
			item.global_position = desk.to_global((desk.to_local(item.global_position) - pivot).rotated(Vector3.UP, -deg_to_rad(delta_degrees)) + pivot)
			item.rotation.y -= deg_to_rad(delta_degrees)
		return false
	return true


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
	var choices := models_for(str(zone.get("category", "Другие")))
	var result: Array[Dictionary] = []
	if choices.is_empty():
		return result
	var count := random.randi_range(1, 3) if bool(zone.get("required", true)) else random.randi_range(0, 2)
	for _i in count:
		result.append({"model": choices[random.randi_range(0, choices.size() - 1)], "x": float(zone["x"]) + random.randf_range(-float(zone["width"]) * 0.33, float(zone["width"]) * 0.33), "z": float(zone["z"]) + random.randf_range(-float(zone["depth"]) * 0.33, float(zone["depth"]) * 0.33)})
	return result


static func move_zone(desk: Node3D, zones: Array[Dictionary], index: int, target: Vector2, stations: Array, attached: Array[Node3D]) -> bool:
	if index < 0 or index >= zones.size():
		return false
	var zone: Dictionary = zones[index]
	var next := snap_to_neighbors(Vector2(snappedf(target.x, 0.05), snappedf(target.y, 0.05)), zone, zones, index)
	if not _inside_surface(next, zone, stations):
		return false
	var current := Vector2(float(zone["x"]), float(zone["z"]))
	var movement := next - current
	if movement.length_squared() < 0.0001:
		return false
	var contents := items_in_zone(desk, zone, attached)
	var proposed := zone.duplicate()
	proposed["x"] = next.x
	proposed["z"] = next.y
	for item in contents:
		item.global_position = desk.to_global(desk.to_local(item.global_position) + Vector3(movement.x, 0, movement.y))
	var outside := false
	for item in contents:
		if not fits_zone(desk, proposed, item):
			outside = true
			break
	if outside or _overlaps(contents, attached):
		for item in contents:
			item.global_position = desk.to_global(desk.to_local(item.global_position) - Vector3(movement.x, 0, movement.y))
		return false
	zone["x"] = next.x
	zone["z"] = next.y
	return true


static func snap_to_neighbors(point: Vector2, zone: Dictionary, zones: Array[Dictionary], index: int) -> Vector2:
	if absf(float(zone.get("angle", 0.0))) > 0.01:
		return point
	for i in zones.size():
		if i == index:
			continue
		var other: Dictionary = zones[i]
		if bool(other["floor"]) != bool(zone["floor"]) or absf(float(other.get("angle", 0.0))) > 0.01:
			continue
		var horizontal := (float(zone["width"]) + float(other["width"])) * 0.5
		var vertical := (float(zone["depth"]) + float(other["depth"])) * 0.5
		if absf(point.y - float(other["z"])) < vertical:
			for sign_value in [-1.0, 1.0]:
				var edge := float(other["x"]) + sign_value * horizontal
				if absf(point.x - edge) < 0.08:
					point.x = edge
		if absf(point.x - float(other["x"])) < horizontal:
			for sign_value in [-1.0, 1.0]:
				var edge := float(other["z"]) + sign_value * vertical
				if absf(point.y - edge) < 0.08:
					point.y = edge
	return point


static func _inside_surface(point: Vector2, zone: Dictionary, stations: Array) -> bool:
	var angle := deg_to_rad(float(zone.get("angle", 0.0)))
	var half_width := absf(cos(angle)) * float(zone["width"]) * 0.5 + absf(sin(angle)) * float(zone["depth"]) * 0.5
	var half_depth := absf(sin(angle)) * float(zone["width"]) * 0.5 + absf(cos(angle)) * float(zone["depth"]) * 0.5
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
