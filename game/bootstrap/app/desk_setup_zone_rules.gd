extends RefCounted

# Move a local placement region and its contents as one transaction.
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const GEOMETRY := preload("res://game/bootstrap/app/desk_setup_zone_geometry.gd")
const CATEGORIES := ["Monitor", "Keyboard", "Mouse", "Laptop", "Drinkware", "Food", "Stationery", "Paper", "Books", "Mini PC", "Tower PC", "Bags", "Bins", "Plants", "Printers", "Desk lamps", "Desk phones", "Other", "Chair"]


static func category_for(model: String) -> String:
	var label := model.to_lower()
	if "chair" in label: return "Chair"
	if "monitor" in label: return "Monitor"
	if "keyboard" in label: return "Keyboard"
	if "laptop" in label: return "Laptop"
	if "mouse" in label: return "Mouse"
	if "minipc" in label: return "Mini PC"
	if "computer_tower" in label or label.begins_with("05_pc_"): return "Tower PC"
	if "mug" in label or label.begins_with("09_glass") or "fruit_plate" in label: return "Drinkware"
	if label.begins_with("09_fruit_") or "snack" in label or "cookies" in label: return "Food"
	if "pencil" in label or label.begins_with("09_pen_") or "marker" in label or "stapler" in label or "tablet" in label: return "Stationery"
	if "casehand" in label or "09_case_" in label: return "Bags"
	if "trash_bin" in label: return "Bins"
	if label.begins_with("11_plant") or "deco_plant" in label or label.begins_with("11_bamboo"): return "Plants"
	if "printer" in label or "mfu" in label: return "Printers"
	if "desklamp" in label or label == "05_lamp": return "Desk lamps"
	if "desk_phone" in label or label.begins_with("09_phone_"): return "Desk phones"
	if "book" in label: return "Books"
	if "paper" in label or "file" in label or "notepad" in label or "binder" in label: return "Paper"
	return "Other"


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
	var old_category := str(zone.get("category", "Other"))
	var aliases := {"Any": "Other", "Computer": "Tower PC", "Glass": "Drinkware", "Mug": "Drinkware", "Pencil": "Stationery", "Pen": "Stationery", "Book": "Books", "Монитор": "Monitor", "Клавиатура": "Keyboard", "Мышь": "Mouse", "Ноутбук": "Laptop", "Стакан": "Drinkware", "Кружка": "Drinkware", "Карандаш": "Stationery", "Ручка": "Stationery", "Бумага": "Paper", "Книги": "Books", "Другие": "Other", "Кресло": "Chair"}
	zone["category"] = aliases.get(old_category, old_category) if aliases.get(old_category, old_category) in CATEGORIES else "Other"
	if zone["name"] == old_category:
		zone["name"] = zone["category"]
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
			# Check the item's placement point and its supporting surface.
			if GEOMETRY.fits_zone(desk, zone, item):
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
	if outside:
		for item in moved:
			item.global_position = desk.to_global((desk.to_local(item.global_position) - pivot).rotated(Vector3.UP, -deg_to_rad(delta_degrees)) + pivot)
			item.rotation.y -= deg_to_rad(delta_degrees)
		return false
	return true


static func random_items(zone: Dictionary) -> Array[Dictionary]:
	var random := RandomNumberGenerator.new()
	random.randomize()
	var choices := models_for(str(zone.get("category", "Other")))
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
	if outside:
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
				var edge: float = float(other["x"]) + sign_value * horizontal
				if absf(point.x - edge) < 0.08:
					point.x = edge
		if absf(point.x - float(other["x"])) < horizontal:
			for sign_value in [-1.0, 1.0]:
				var edge: float = float(other["z"]) + sign_value * vertical
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
		if absf(float(zone.get("height", 0.89)) - float(station.get("grid_height", zone.get("height", 0.89)))) > 0.04:
			continue
		if absf(point.x - float(station.get("x", 0.0))) + half_width <= float(station.get("usable_width", 1.9)) * 0.5 and absf(point.y - float(station.get("z", 0.0))) + half_depth <= float(station.get("usable_depth", 1.2)) * 0.5:
			return true
	return false
