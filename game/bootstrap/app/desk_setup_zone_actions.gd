extends RefCounted

const RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const GEOMETRY := preload("res://game/bootstrap/app/desk_setup_zone_geometry.gd")
const MODEL_ROOT := "res://models/objects/enviroments/"


static func add_at(mode: Variant, screen: Vector2) -> void:
	var tabletop_height: float = float(mode.markers.get("surface_height"))
	if mode.zone_index >= 0 and not bool(mode.zones[mode.zone_index].get("floor", false)):
		tabletop_height = float(mode.zones[mode.zone_index].get("height", tabletop_height))
	var table_point: Vector3 = mode._project(screen, tabletop_height)
	var table_local: Vector3 = mode.desk.to_local(table_point)
	var zone_width := 0.65
	var zone_depth := 0.45
	if mode.shelf_mode:
		for station_value in mode.stations:
			var station: Dictionary = station_value
			if absf(float(station.get("grid_height", 0.0)) - tabletop_height) < 0.04:
				zone_width = minf(zone_width, float(station.get("zone_width", zone_width)))
				zone_depth = minf(zone_depth, float(station.get("zone_depth", zone_depth)))
				break
	var preview := {"x": table_local.x, "z": table_local.z, "width": zone_width, "depth": zone_depth, "angle": 0.0, "floor": false, "height": tabletop_height}
	var on_table: bool = table_local.is_finite() and RULES._inside_surface(Vector2(table_local.x, table_local.z), preview, mode.stations)
	if mode.shelf_mode and not on_table:
		mode.status.text = "Zone must fit on the selected shelf."
		return
	var point: Vector3 = table_point if on_table else mode._project(screen, 0.0)
	if not point.is_finite():
		return
	var local: Vector3 = mode.desk.to_local(point)
	var zone := {"name": "Zone %d" % (mode.zones.size() + 1), "required": false, "category": "Other", "angle": 0.0, "x": snappedf(local.x, 0.05), "z": snappedf(local.z, 0.05), "width": zone_width, "depth": zone_depth, "height": tabletop_height if on_table else 0.0, "floor": not on_table}
	var center: Vector2 = RULES.snap_to_neighbors(Vector2(zone["x"], zone["z"]), zone, mode.zones, -1)
	zone["x"] = center.x
	zone["z"] = center.y
	if not RULES._inside_surface(Vector2(zone["x"], zone["z"]), zone, mode.stations):
		mode.status.text = "Zone must fit on the selected surface."
		return
	mode.zones.append(zone)
	mode.zone_index = mode.zones.size() - 1
	mode.placing_zone = false
	mode._refresh_zones()


static func surface_label(mode: Variant, zone: Dictionary) -> String:
	if mode.shelf_mode:
		for index in mode.stations.size():
			if absf(float(zone.get("height", 0.0)) - float(mode.stations[index].get("grid_height", 0.0))) < 0.04:
				return "Shelf %d" % (index + 1)
		return "Shelf"
	return "Floor" if bool(zone.get("floor", false)) else "Table"


static func clear_selection(mode: Variant) -> void:
	mode.dragged = null
	mode.dragging_zone = false
	mode.placing_zone = false
	mode.chair_positioning = false
	mode.zone_index = -1
	mode.model_list.deselect_all()
	mode.model_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode.zone_form.hide()
	if mode.model_list.has_meta("placing"):
		mode.model_list.remove_meta("placing")
	mode.planner._select(null)
	mode._refresh_zones()
	mode.status.text = "Selection cleared. Select a zone to continue."


static func duplicate_zone(mode: Variant, index: int) -> void:
	if index < 0 or index >= mode.zones.size():
		return
	var source: Dictionary = mode.zones[index]
	var copy := source.duplicate(true)
	copy["name"] = str(source.get("name", "Zone")) + " (copy)"
	var original := Vector2(float(source["x"]), float(source["z"]))
	var destination := original
	var offsets := [Vector2(float(source["width"]), 0.0), Vector2(-float(source["width"]), 0.0), Vector2(0.0, float(source["depth"])), Vector2(0.0, -float(source["depth"]))]
	for offset in offsets:
		if RULES._inside_surface(original + offset, copy, mode.stations):
			destination = original + offset
			break
	copy["x"] = destination.x
	copy["z"] = destination.y
	var items := RULES.items_in_zone(mode.desk, source, mode._attachments())
	var new_index: int = mode.zones.size()
	mode.zones.append(copy)
	var displacement: Vector3 = mode.desk.to_global(Vector3(destination.x, 0.0, destination.y)) - mode.desk.to_global(Vector3(original.x, 0.0, original.y))
	var skipped := 0
	for original_item in items:
		var path := str(original_item.get_meta("planning_scene_path", ""))
		if not path.begins_with(MODEL_ROOT) or not FileAccess.file_exists(path):
			skipped += 1
			continue
		var item: Node3D = mode.planner._instantiate_asset(path) as Node3D
		if item == null:
			skipped += 1
			continue
		mode.planner.root.add_child(item)
		item.global_transform = original_item.global_transform
		item.global_position += displacement
		item.set_meta("planning_scene_path", path)
		item.set_meta("planning_attachment", mode._desk_id())
		item.set_meta("planning_zone", new_index)
		mode.planner.placed.append(item)
	mode.zone_index = new_index
	mode._refresh_zones()
	mode.status.text = "Zone and items copied. Drag the copy to a new position." if destination == original else "Zone and items copied."
	if skipped > 0:
		mode.status.text += " Missing models: %d." % skipped


static func refresh_models(mode: Variant) -> void:
	var category := str(mode.zones[mode.zone_index].get("category", "Other")) if mode.zone_index >= 0 else "Other"
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
	if mode.shelf_mode:
		var current := -1
		for index in mode.stations.size():
			if absf(float(zone.get("height", 0.0)) - float(mode.stations[index].get("grid_height", 0.0))) < 0.04:
				current = index
				break
		var next: int = (current + 1) % int(mode.stations.size())
		var target_height := float(mode.stations[next].get("grid_height", 0.0))
		var shelf_proposal := zone.duplicate()
		shelf_proposal["height"] = target_height
		shelf_proposal["floor"] = false
		if not RULES._inside_surface(Vector2(float(zone["x"]), float(zone["z"])), shelf_proposal, mode.stations):
			mode.status.text = "Zone does not fit on this shelf."
			return
		var shelf_surface_y: float = mode.desk.to_global(Vector3.UP * target_height).y
		for item in RULES.items_in_zone(mode.desk, zone, mode._attachments()):
			var local: Vector3 = mode.desk.to_local(item.global_position)
			item.global_position.y += _support_y(mode, item, local, target_height, shelf_surface_y) - WORKSTATIONS._bounds(item).position.y
		zone["height"] = target_height
		zone["floor"] = false
		mode.status.text = "Moved to shelf %d." % (next + 1)
		return
	var proposed := zone.duplicate()
	proposed["floor"] = not bool(zone["floor"])
	proposed["height"] = 0.0 if bool(proposed["floor"]) else mode.markers.surface_height
	var original := Vector2(float(zone["x"]), float(zone["z"]))
	var destination := original
	if not RULES._inside_surface(destination, proposed, mode.stations):
		var angle := deg_to_rad(float(proposed.get("angle", 0.0)))
		var half_width := absf(cos(angle)) * float(proposed["width"]) * 0.5 + absf(sin(angle)) * float(proposed["depth"]) * 0.5
		var half_depth := absf(sin(angle)) * float(proposed["width"]) * 0.5 + absf(cos(angle)) * float(proposed["depth"]) * 0.5
		if bool(proposed["floor"]) and half_width <= 2.75 and half_depth <= 2.75:
			destination = Vector2(clampf(original.x, -2.75 + half_width, 2.75 - half_width), clampf(original.y, -2.75 + half_depth, 2.75 - half_depth))
		else:
			var found := false
			for station_value in mode.stations:
				var station: Dictionary = station_value
				var available_width := float(station.get("usable_width", 1.9)) * 0.5
				var available_depth := float(station.get("usable_depth", 1.2)) * 0.5
				if half_width > available_width or half_depth > available_depth:
					continue
				var center := Vector2(float(station.get("x", 0.0)), float(station.get("z", 0.0)))
				var candidate := Vector2(clampf(original.x, center.x - available_width + half_width, center.x + available_width - half_width), clampf(original.y, center.y - available_depth + half_depth, center.y + available_depth - half_depth))
				if not found or candidate.distance_squared_to(original) < destination.distance_squared_to(original):
					destination = candidate
					found = true
	if not RULES._inside_surface(destination, proposed, mode.stations):
		mode.status.text = "Zone does not fit on this surface."
		return
	var contents := RULES.items_in_zone(mode.desk, zone, mode._attachments())
	var displacement: Vector3 = mode.desk.to_global(Vector3(destination.x, 0.0, destination.y)) - mode.desk.to_global(Vector3(original.x, 0.0, original.y))
	var surface_y: float = mode.desk.to_global(Vector3.UP * float(proposed["height"])).y
	for item in contents:
		item.global_position += displacement
		var item_local: Vector3 = mode.desk.to_local(item.global_position)
		item.global_position.y += _support_y(mode, item, item_local, float(proposed["height"]), surface_y) - WORKSTATIONS._bounds(item).position.y
	zone["x"] = destination.x
	zone["z"] = destination.y
	zone["floor"] = proposed["floor"]
	zone["height"] = proposed["height"]
	mode.status.text = "Zone and items moved to floor." if bool(zone["floor"]) else "Zone and items moved to table."


static func place_model(mode: Variant, model: String, local: Vector3) -> void:
	if mode.zone_index < 0 or mode.zone_index >= mode.zones.size():
		mode._notify_failure("Select a zone before adding an item.")
		return
	var zone: Dictionary = mode.zones[mode.zone_index]
	if RULES.category_for(model) != str(zone["category"]):
		mode._notify_failure("%s is in %s; this zone accepts %s." % [model, RULES.category_for(model), str(zone["category"])])
		return
	var path := MODEL_ROOT + model.substr(0, 2) + "/" + model + ".glb"
	if not FileAccess.file_exists(path):
		mode._notify_failure("Model file is missing: " + model)
		return
	var object: Node3D = mode.planner._instantiate_asset(path) as Node3D
	if object == null:
		mode._notify_failure("Cannot load model: " + model)
		return
	mode.planner.root.add_child(object)
	object.rotation.y = mode.desk.rotation.y + deg_to_rad(float(zone.get("angle", 0.0)))
	object.global_position = mode.desk.to_global(Vector3(local.x, float(zone["height"]), local.z))
	var bounds := WORKSTATIONS._bounds(object)
	if bounds.size.length_squared() < 0.000001:
		object.queue_free()
		mode._notify_failure("Model has no visible geometry: " + model)
		return
	var expected_y: float = mode.desk.to_global(Vector3.UP * float(zone["height"])).y
	object.global_position.y += _support_y(mode, object, local, float(zone["height"]), expected_y) - bounds.position.y
	var issue: String = GEOMETRY.fit_issue(mode.desk, zone, object)
	if not issue.is_empty():
		object.queue_free()
		mode._notify_failure("Cannot place %s: %s" % [model, issue])
		return
	object.set_meta("planning_scene_path", path)
	object.set_meta("planning_attachment", mode._desk_id())
	object.set_meta("planning_zone", mode.zone_index)
	mode.planner.placed.append(object)
	mode._refresh_zone_items()
	mode.status.text = "Placed " + model


static func _support_y(mode: Variant, item: Node3D, local: Vector3, height: float, expected_y: float) -> float:
	if height < 0.02:
		return expected_y
	# Match the visible object's bottom to the actual tabletop. Profiles are guides,
	# and imported meshes may differ from their nominal authored heights.
	var start: Vector3 = mode.desk.to_global(Vector3(local.x, height + 0.38, local.z))
	var end: Vector3 = mode.desk.to_global(Vector3(local.x, height - 0.28, local.z))
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.collide_with_areas = false
	if item is CollisionObject3D:
		query.exclude = [(item as CollisionObject3D).get_rid()]
	var hit: Dictionary = mode.desk.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.get("collider") == mode.desk:
		var actual_y: float = (hit["position"] as Vector3).y
		if absf(actual_y - expected_y) < 0.28:
			return maxf(actual_y + 0.005, expected_y)
	return expected_y


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
			label.text = "OUTSIDE ZONE: " + str(object.get_meta("planning_scene_path", object.name)).get_file().get_basename()
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
		if str(mode.zones[i].get("category", "")) == "Chair" and bool(mode.zones[i]["floor"]):
			index = i
			break
	if index < 0:
		mode.zones.append({"name": "Chair", "required": true, "category": "Chair", "angle": 0.0, "x": target.x, "z": target.y, "width": 1.45, "depth": 1.45, "height": 0.0, "floor": true})
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
