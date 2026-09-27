extends RefCounted

const TEMPLATE_FILES := preload("res://game/bootstrap/app/desk_setup_template_files.gd")
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const ZONE_RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")
const MODEL_ROOT := "res://models/objects/enviroments/"


static func save(mode: Variant) -> void:
	if TEMPLATE_FILES.safe_name(mode.template_name.text).is_empty():
		mode.status.text = "Enter a template name first."
		return
	for zone in mode.zones:
		if bool(zone.get("required", true)) and ZONE_RULES.items_in_zone(mode.desk, zone, mode._attachments()).is_empty():
			mode.status.text = "Required zone is empty: " + str(zone["name"])
			return
	var items: Array[Dictionary] = []
	for object in mode._attachments():
		var local: Vector3 = mode.desk.to_local(object.global_position)
		items.append({"path": str(object.get_meta("planning_scene_path", "")), "x": local.x, "y": local.y, "z": local.z, "yaw": object.rotation.y - mode.desk.rotation.y})
	var desk_type := WORKSTATIONS.desk_name(mode._desk_path())
	if not TEMPLATE_FILES.save(desk_type, mode.template_name.text, {"version": 1, "desk": desk_type, "front": mode.front, "zones": mode.zones, "items": items}):
		mode.status.text = "Could not save the template."
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
		return
	var path: String = mode.template_list.get_item_metadata(mode.template_list.selected)
	var data: Dictionary = TEMPLATE_FILES.load(path, WORKSTATIONS.desk_name(mode._desk_path()))
	if data.is_empty():
		mode.status.text = "Template does not match this desk."
		return
	for object in mode._attachments():
		mode.planner.placed.erase(object)
		object.queue_free()
	mode.zones.clear()
	for value in data.get("zones", []):
		if value is Dictionary:
			mode.zones.append(ZONE_RULES.normalize(value, mode.zones.size()))
	mode.front = int(data.get("front", 0))
	mode.front_button.text = "Front: opposite side" if mode.front else "Front: seated side"
	mode.zone_index = 0 if not mode.zones.is_empty() else -1
	mode._refresh_zones()
	for entry_value in data.get("items", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var asset_path := str(entry.get("path", ""))
		if not asset_path.begins_with(MODEL_ROOT) or not FileAccess.file_exists(asset_path):
			continue
		var object: Node3D = mode.planner._instantiate_asset(asset_path) as Node3D
		if object == null:
			continue
		mode.planner.root.add_child(object)
		object.global_position = mode.desk.to_global(Vector3(float(entry.get("x", 0)), float(entry.get("y", 0)), float(entry.get("z", 0))))
		object.rotation.y = mode.desk.rotation.y + float(entry.get("yaw", 0))
		object.set_meta("planning_scene_path", asset_path)
		object.set_meta("planning_attachment", mode._desk_id())
		mode.planner.placed.append(object)
	mode.status.text = "Template applied to this desk. Save the map to keep it."
	mode._refresh_zone_items()
