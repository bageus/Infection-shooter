extends RefCounted

const RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")


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
