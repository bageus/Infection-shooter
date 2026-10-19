extends RefCounted

const TEMPLATE_FILES := preload("res://game/bootstrap/app/desk_setup_template_files.gd")
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const ZONE_RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")
const GEOMETRY := preload("res://game/bootstrap/app/desk_setup_zone_geometry.gd")


static func save(mode: Variant) -> void:
	if TEMPLATE_FILES.safe_name(mode.template_name.text).is_empty():
		mode._notify_failure("Enter a template name first.")
		return
	for zone in mode.zones:
		if bool(zone.get("required", true)) and ZONE_RULES.items_in_zone(mode.desk, zone, mode._attachments()).is_empty():
			mode._notify_failure("Required zone is empty: " + str(zone["name"]))
			return
	var items: Array[Dictionary] = []
	for object in mode._attachments():
		var slot := GEOMETRY.matching_zone(mode.desk, mode.zones, object, int(object.get_meta("planning_zone", -1)))
		if slot < 0:
			mode._notify_failure("Move or remove the object outside a zone: " + object.name)
			return
		if ZONE_RULES.category_for(str(object.get_meta("planning_scene_path", "")).get_file().get_basename()) != str(mode.zones[slot]["category"]):
			mode._notify_failure("Object has the wrong type for its zone: " + object.name)
			return
		var local: Vector3 = mode.desk.to_local(object.global_position)
		items.append({"path": str(object.get_meta("planning_scene_path", "")), "zone": slot, "x": local.x, "y": local.y, "z": local.z, "yaw": object.rotation.y - mode.desk.rotation.y, "tilt_x": object.rotation.x, "tilt_z": object.rotation.z})
	var desk_type := WORKSTATIONS.desk_name(mode._desk_path())
	if desk_type.is_empty():
		mode._notify_failure("This desk model has no template profile: " + mode._desk_path().get_file())
		return
	if not TEMPLATE_FILES.save(desk_type, mode.template_name.text, {"version": 1, "desk": desk_type, "front": mode.front, "zones": mode.zones, "items": items}):
		mode._notify_failure("Could not write the desk template to user://desk_setups.")
		return
	refresh(mode)
	mode.status.text = "Saved: " + mode.template_name.text


static func refresh(mode: Variant) -> void:
	mode.template_list.clear()
	for item in TEMPLATE_FILES.list_for(WORKSTATIONS.desk_name(mode._desk_path())):
		mode.template_list.add_item(str(item["name"]))
		mode.template_list.set_item_metadata(mode.template_list.item_count - 1, item["path"])


static func load_selected(mode: Variant) -> void:
	if mode.template_list.selected < 0:
		mode._notify_failure("Select a saved template before applying it.")
		return
	var path: String = mode.template_list.get_item_metadata(mode.template_list.selected)
	var data: Dictionary = TEMPLATE_FILES.load(path, WORKSTATIONS.desk_name(mode._desk_path()))
	if data.is_empty():
		mode._notify_failure("Template does not match this desk.")
		return
	var prepared := _prepare(mode, data)
	if prepared.is_empty():
		mode._notify_failure("Template could not be applied. The current desk setup was kept.")
		return
	# No awaits: the old setup survives until every replacement has passed.
	var attachment_id: String = mode._desk_id()
	for object in mode._attachments():
		mode.planner.placed.erase(object)
		object.queue_free()
	mode.zones.assign(prepared.zones)
	mode.front = int(data.get("front", 0))
	mode.front_button.text = "Front: opposite side" if mode.front else "Front: seated side"
	mode.zone_index = 0 if not mode.zones.is_empty() else -1
	for object: Node3D in prepared.items:
		object.reparent(mode.planner.root, true)
		object.set_meta("planning_attachment", attachment_id)
		mode.planner.placed.append(object)
	(prepared.stage as Node).free()
	mode._refresh_zones()
	mode._refresh_zone_items()
	mode.status.text = "Template applied to this desk. Save the map to keep it."


## Geometry needs in-tree visible meshes. This container lives only during this
## synchronous call, with processing disabled; no partial setup reaches a frame.
static func _prepare(mode: Variant, data: Dictionary) -> Dictionary:
	var zones: Array[Dictionary] = []
	for value: Dictionary in data.zones:
		var zone := ZONE_RULES.normalize(value.duplicate(true), zones.size())
		zone["slot"] = zones.size()
		if not ZONE_RULES._inside_surface(Vector2(float(zone.x), float(zone.z)), zone, mode.stations):
			return {}
		zones.append(zone)
	var stage := Node3D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	mode.planner.root.add_child(stage)
	var items: Array[Node3D] = []
	for entry: Dictionary in data.items:
		var position: Vector3 = mode.desk.to_global(Vector3(float(entry.x), float(entry.y), float(entry.z)))
		if not position.is_finite():
			stage.free()
			return {}
		var object: Node3D = mode.planner._instantiate_asset(str(entry.path)) as Node3D
		if object == null:
			stage.free()
			return {}
		stage.add_child(object)
		object.global_position = position
		object.rotation = Vector3(float(entry.get("tilt_x", 0.0)), mode.desk.rotation.y + float(entry.get("yaw", 0)), float(entry.get("tilt_z", 0.0)))
		var slot := GEOMETRY.matching_zone(mode.desk, zones, object, int(entry.get("zone", -1)))
		if slot < 0 or (data.zones[slot].has("category") and ZONE_RULES.category_for(str(entry.path).get_file().get_basename()) != str(zones[slot].category)):
			stage.free()
			return {}
		object.set_meta("planning_scene_path", str(entry.path))
		object.set_meta("planning_zone", slot)
		items.append(object)
	for zone in zones:
		if bool(zone.required) and ZONE_RULES.items_in_zone(mode.desk, zone, items).is_empty():
			stage.free()
			return {}
	return {"zones": zones, "items": items, "stage": stage}
