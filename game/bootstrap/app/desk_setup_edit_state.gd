extends RefCounted
## Session-local edit snapshots; legacy maps derive typed zones from attachments.
const RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
var _snapshots: Dictionary = {}


func remember(mode: Node) -> void:
	if is_instance_valid(mode.desk):
		_snapshots[mode.desk.get_instance_id()] = {"desk": weakref(mode.desk), "zones": mode.zones.duplicate(true), "front": mode.front}


func restore(mode: Node) -> void:
	for key: int in _snapshots.keys():
		if _snapshots[key].desk.get_ref() == null:
			_snapshots.erase(key)
	if mode.desk.has_meta("planning_template_edit"):
		var initial: Dictionary = mode.desk.get_meta("planning_template_edit")
		mode.zones.assign(initial.zones.duplicate(true))
		for index in mode.zones.size():
			RULES.normalize(mode.zones[index], index)
		mode.front = int(initial.front)
		mode.desk.remove_meta("planning_template_edit")
		return
	var saved: Dictionary = _snapshots.get(mode.desk.get_instance_id(), {})
	if not saved.is_empty() and saved.desk.get_ref() == mode.desk:
		mode.zones.assign(saved.zones.duplicate(true))
		mode.front = int(saved.front)
		return
	_restore_attachments(mode)


func _restore_attachments(mode: Node) -> void:
	# Maps store actual objects, not editor zones. Rebuild one zone per category
	# and supporting surface instead of assigning every item to an Other zone.
	var attachments: Array[Node3D] = mode._attachments()
	if attachments.is_empty():
		return
	var defaults: Array = mode.zones.duplicate(true)
	var default_height := float(defaults[0].get("height", 0.89)) if not defaults.is_empty() else 0.89
	mode.zones.clear()
	for item: Node3D in attachments:
		var category := RULES.category_for(str(item.get_meta("planning_scene_path", "")).get_file().get_basename())
		var bottom := WORKSTATIONS._bounds(item).position.y
		var point: Vector3 = mode.desk.to_local(item.global_position)
		var height := 0.0
		var surface: Dictionary = {}
		var distance := absf(bottom - mode.desk.to_global(Vector3.ZERO).y)
		for station: Dictionary in mode.stations:
			var candidate := float(station.get("grid_height", default_height))
			var difference := absf(bottom - mode.desk.to_global(Vector3.UP * candidate).y)
			var dx := maxf(absf(point.x - float(station.get("x", 0.0))) - float(station.get("usable_width", 1.9)) * 0.5, 0.0)
			var dz := maxf(absf(point.z - float(station.get("z", 0.0))) - float(station.get("usable_depth", 1.2)) * 0.5, 0.0)
			difference += Vector2(dx, dz).length()
			if difference < distance:
				distance = difference
				height = candidate
				surface = station
		var zone := {"name": category, "category": category, "required": false, "angle": 0.0,
			"height": height, "floor": surface.is_empty(), "x": float(surface.get("x", 0.0)),
			"z": float(surface.get("z", 0.0)), "width": float(surface.get("usable_width", 5.5)),
			"depth": float(surface.get("usable_depth", 5.5))}
		var slot: int = mode.zones.find(zone)
		if slot < 0:
			slot = mode.zones.size()
			mode.zones.append(zone)
		item.set_meta("planning_zone", slot)

	for zone: Dictionary in defaults:
		var used := false
		for restored: Dictionary in mode.zones:
			used = used or (bool(restored.floor) == bool(zone.floor) and absf(float(restored.height) - float(zone.height)) < 0.04 and Vector2(restored.x, restored.z).distance_to(Vector2(zone.x, zone.z)) < 0.04)
		if not used:
			mode.zones.append(zone)


func pick(mode: Node, screen: Vector2) -> Node3D:
	# A shelf's enclosing AABB must not hide the editable items inside it.
	var origin: Vector3 = mode.planner.camera.project_ray_origin(screen)
	var direction: Vector3 = mode.planner.camera.project_ray_normal(screen)
	var best: Node3D
	var nearest := INF
	for item: Node3D in mode._attachments():
		var bounds: AABB = mode.planner.geometry._combined_aabb(item)
		var hit: Variant = (item.global_transform * bounds).intersects_ray(origin, direction)
		if hit is Vector3 and origin.distance_to(hit) < nearest:
			nearest = origin.distance_to(hit)
			best = item
	return best


func drag(mode: Node, screen: Vector2) -> void:
	if not is_instance_valid(mode.dragged) or mode.zone_index < 0 or mode.zone_index >= mode.zones.size():
		return
	var zone: Dictionary = mode.zones[mode.zone_index]
	var local: Vector3 = mode._local_at(screen, zone)
	if not local.is_finite() or not mode._point_in_zone(mode.zone_index, screen):
		return
	var previous: Vector3 = mode.dragged.global_position
	mode.dragged.global_position = mode.desk.to_global(Vector3(local.x, mode.desk.to_local(previous).y, local.z))
	var category := RULES.category_for(str(mode.dragged.get_meta("planning_scene_path", "")).get_file().get_basename())
	if category != str(zone["category"]) or not RULES.fits_zone(mode.desk, zone, mode.dragged):
		mode.dragged.global_position = previous
	else:
		var previous_slot := int(mode.dragged.get_meta("planning_zone", -1))
		mode.dragged.set_meta("planning_zone", mode.zone_index)
		if previous_slot != mode.zone_index:
			mode._refresh_zone_items()
