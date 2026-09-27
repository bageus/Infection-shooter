extends RefCounted

const RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const GEOMETRY := preload("res://game/bootstrap/app/desk_setup_zone_geometry.gd")
const MODEL_ROOT := "res://models/objects/enviroments/"


static func refresh_models(mode: Variant) -> void:
	var category := str(mode.zones[mode.zone_index].get("category", "Другие")) if mode.zone_index >= 0 else "Другие"
	if mode.shown_category == category:
		return
	mode.shown_category = category
	mode.model_list.clear()
	mode.models = RULES.models_for(category)
	for model in mode.models:
		mode.model_list.add_item(model)
	if mode.model_list.has_meta("placing"):
		mode.model_list.remove_meta("placing")


static func resize_zone(mode: Variant) -> void:
	if mode.zone_index < 0:
		return
	var zone: Dictionary = mode.zones[mode.zone_index]
	var proposed := zone.duplicate()
	proposed["width"] = mode.width_field.value
	proposed["depth"] = mode.depth_field.value
	var point := Vector2(float(zone["x"]), float(zone["z"]))
	var allowed := RULES._inside_surface(point, proposed, mode.stations)
	if allowed:
		for item in RULES.items_in_zone(mode.desk, zone, mode._attachments()):
			if not RULES.fits_zone(mode.desk, proposed, item):
				allowed = false
				break
	if not allowed:
		mode.width_field.set_value_no_signal(float(zone["width"]))
		mode.depth_field.set_value_no_signal(float(zone["depth"]))
		mode.status.text = "Zone would leave the surface or exclude an item."
		return
	zone["width"] = proposed["width"]
	zone["depth"] = proposed["depth"]
	mode._refresh_markers()


static func toggle_surface(mode: Variant) -> void:
	if mode.zone_index < 0:
		return
	var zone: Dictionary = mode.zones[mode.zone_index]
	if not RULES.items_in_zone(mode.desk, zone, mode._attachments()).is_empty():
		mode.status.text = "Remove zone items before moving the zone between table and floor."
		return
	var proposed := zone.duplicate()
	proposed["floor"] = not bool(zone["floor"])
	proposed["height"] = 0.0 if bool(proposed["floor"]) else mode.markers.surface_height
	if not RULES._inside_surface(Vector2(float(zone["x"]), float(zone["z"])), proposed, mode.stations):
		mode.status.text = "Zone does not fit on this surface."
		return
	zone["floor"] = proposed["floor"]
	zone["height"] = proposed["height"]
	mode._refresh_zones()


static func place_model(mode: Variant, model: String, local: Vector3) -> void:
	var zone: Dictionary = mode.zones[mode.zone_index]
	if RULES.category_for(model) != str(zone["category"]):
		mode.status.text = "Choose an item of type: " + str(zone["category"])
		return
	var path := MODEL_ROOT + model.substr(0, 2) + "/" + model + ".glb"
	if not FileAccess.file_exists(path):
		return
	var existing: Array[Node3D] = []
	for object in mode.planner.placed:
		if is_instance_valid(object) and object != mode.desk and object.get_meta("planning_attachment", "") != mode._desk_id():
			existing.append(object)
	var occupied: Array[Rect2] = []
	for object in mode._attachments():
		var bounds: AABB = WORKSTATIONS._bounds(object)
		occupied.append(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(0.015))
	var created: Array[Node3D] = []
	var random := RandomNumberGenerator.new()
	random.randomize()
	var entry := {"model": model, "x": 0.0, "z": 0.0, "jitter": 0.0, "rotation_jitter": 0.0, "floor": bool(zone["floor"])}
	WORKSTATIONS._add_item(entry, {"x": local.x, "z": local.z, "angle": float(zone.get("angle", 0.0))}, float(zone["height"]), mode.desk, mode.planner.root, existing, created, occupied, random, Callable(mode.planner, "_instantiate_asset"))
	var accepted := 0
	for object in created:
		if not RULES.fits_zone(mode.desk, zone, object):
			object.queue_free()
			continue
		object.set_meta("planning_attachment", mode._desk_id())
		object.set_meta("planning_zone", mode.zone_index)
		mode.planner.placed.append(object)
		accepted += 1
	mode._refresh_zone_items()
	mode.status.text = "Placed " + model if accepted > 0 else "Object does not fit inside the zone or overlaps another item."


static func refresh_items(mode: Variant) -> void:
	for child in mode.zone_items.get_children():
		mode.zone_items.remove_child(child)
		child.queue_free()
	if mode.zone_index < 0 or mode.desk == null:
		return
	for object in RULES.items_in_zone(mode.desk, mode.zones[mode.zone_index], mode._attachments()):
		var row := HBoxContainer.new()
		mode.zone_items.add_child(row)
		var label := Label.new()
		label.text = str(object.get_meta("planning_scene_path", object.name)).get_file().get_basename()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		mode._button(row, "×", Callable(mode, "_remove_zone_item").bind(object))
	if mode.zone_index == 0:
		for object in mode._attachments():
			if GEOMETRY.matching_zone(mode.desk, mode.zones, object, int(object.get_meta("planning_zone", -1))) >= 0:
				continue
			var row := HBoxContainer.new()
			mode.zone_items.add_child(row)
			var label := Label.new()
			label.text = "ВНЕ ЗОНЫ: " + str(object.get_meta("planning_scene_path", object.name)).get_file().get_basename()
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			mode._button(row, "×", Callable(mode, "_remove_zone_item").bind(object))


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
	if absf(target.x) > 2.0 or absf(target.y) > 2.0:
		mode.status.text = "Choose a spot near the desk."
		return
	var index := -1
	for i in mode.zones.size():
		if str(mode.zones[i].get("category", "")) == "Кресло" and bool(mode.zones[i]["floor"]):
			index = i
			break
	if index < 0:
		mode.zones.append({"name": "Кресло", "required": true, "category": "Кресло", "angle": 0.0, "x": target.x, "z": target.y, "width": 1.45, "depth": 1.45, "height": 0.0, "floor": true})
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
