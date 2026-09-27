extends RefCounted

const RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")


static func choose_chair(mode: Variant) -> void:
	mode.chair_positioning = true
	mode.placing_zone = false
	mode.status.text = "Click the floor to place or move the chair. Drag its zone or use arrow keys afterwards."


static func place_chair(mode: Variant, screen: Vector2) -> void:
	var point: Vector3 = mode._project(screen, 0.0)
	if not point.is_finite():
		return
	var local: Vector3 = mode.desk.to_local(point)
	var target := Vector2(snappedf(local.x, 0.05), snappedf(local.z, 0.05))
	if absf(target.x) > 2.25 or absf(target.y) > 2.25:
		mode.status.text = "Choose a spot near the desk."
		return
	var index := -1
	for i in mode.zones.size():
		if str(mode.zones[i].get("category", "")) == "Chair" and bool(mode.zones[i]["floor"]):
			index = i
			break
	if index < 0:
		mode.zones.append({"name": "Chair", "required": true, "category": "Chair", "angle": 0.0, "x": target.x, "z": target.y, "width": 0.9, "depth": 0.9, "height": 0.0, "floor": true})
		index = mode.zones.size() - 1
	elif not RULES.move_zone(mode.desk, mode.zones, index, target, mode.stations, mode._attachments()):
		mode.status.text = "No room for the chair at this position."
		return
	mode.zone_index = index
	mode._clear_zone()
	mode._place_model(mode.chair_model.get_item_text(mode.chair_model.selected), Vector3(target.x, 0, target.y))
	mode.chair_positioning = false
	mode._refresh_zones()


static func randomize(mode: Variant) -> void:
	if mode.zone_index < 0:
		return
	mode._clear_zone()
	var zone: Dictionary = mode.zones[mode.zone_index]
	for item in RULES.random_items(zone):
		mode._place_model(str(item["model"]), Vector3(float(item["x"]), float(zone["height"]), float(item["z"])))
	if bool(zone.get("required", true)):
		for _attempt in 8:
			if not RULES.items_in_zone(mode.desk, zone, mode._attachments()).is_empty():
				break
			var candidates: Array[Dictionary] = RULES.random_items(zone)
			if candidates.is_empty():
				break
			var choice: Dictionary = candidates[0]
			mode._place_model(str(choice["model"]), Vector3(float(choice["x"]), float(zone["height"]), float(choice["z"])))
		if RULES.items_in_zone(mode.desk, zone, mode._attachments()).is_empty():
			mode.status.text = "No room for an item in required zone: " + str(zone["name"])
			return
	mode.status.text = "Random preview: " + str(zone["name"])
