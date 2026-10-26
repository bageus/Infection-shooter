extends RefCounted
## Planner owns the source records; office_floor owns baked page pixels and views.
const VIEW := preload("res://game/presentation/office_floor/public/baked_biomass_floor.gd")
const LIGHT := preload("res://game/bootstrap/app/planning_biomass_light_bake.gd")
const SURFACE := preload("res://game/bootstrap/app/planning_surface_decals.gd")
const KEY := &"floor_biomass_v1"
const VIEW_NAME := "BakedFloorBiomass"


static func bake(session: Node, data: Dictionary, status: Label) -> Dictionary:
	var builder := VIEW.baker()
	if not data.objects.any(func(record: Dictionary) -> bool: return builder.eligible(record)): return {}
	var floor_view := SURFACE.floor_for(session)
	if floor_view == null: return {}
	var host: Node3D = session.get("host")
	var check := func() -> bool: return is_instance_valid(session) and session.is_inside_tree()
	var progress := func(message: String) -> void:
		if is_instance_valid(status): status.text = message
	var light := LIGHT.new()
	light.configure(host, check)
	var size: Vector2 = floor_view.get("floor_size")
	var origin := Vector2(floor_view.global_position.x, floor_view.global_position.z)
	var height := floor_view.global_position.y + float(floor_view.get("tile_y")) + 0.0125
	for opening: Rect2 in floor_view.get("openings"):
		builder.exclusions.append(Rect2(opening.position + origin, opening.size))
	return await builder.build(data.objects, Rect2(origin - size * 0.5, size), height, session.get_tree(), check, progress, light.sample)


static func restore(session: Variant, raw: Dictionary) -> void:
	if not session is Node: return
	var container: Node = session.get("root")
	if not is_instance_valid(container): return
	var existing := container.get_node_or_null(VIEW_NAME)
	if existing != null: existing.free()
	if raw.is_empty():
		for child in container.get_children():
			if child.has_method("set_floor_biomass_baked"): child.call("set_floor_biomass_baked", false)
		if container.has_meta(KEY): container.remove_meta(KEY)
		return
	if not VIEW.valid(raw): return
	container.set_meta(KEY, raw)
	var view := VIEW.new()
	view.name = VIEW_NAME
	view.cache = raw
	container.add_child(view)
	view.visible = not bool(session.get("active"))
	for child in container.get_children():
		if child.has_method("set_floor_biomass_baked"):
			child.call("set_floor_biomass_baked", view.visible)


static func editing(session: Node, enabled: bool) -> void:
	var container: Node = session.get("root")
	if not is_instance_valid(container): return
	var view := container.get_node_or_null(VIEW_NAME)
	if view != null:
		var storage: Variant = session.get("storage")
		var data: Dictionary = storage.authored_layout if storage != null else {}
		var current := signature(data.get("objects", []))
		view.visible = not enabled and current == str(view.cache.get("source_signature", ""))
		for child in container.get_children():
			if child.has_method("set_floor_biomass_baked"):
				child.call("set_floor_biomass_baked", view.visible)


static func capture(session: Variant, data: Dictionary) -> void:
	if session is Node:
		var container: Variant = session.get("root")
		if is_instance_valid(container) and container.has_meta(KEY): data[KEY] = container.get_meta(KEY)


## JSON parses integer literals as floats; normalize saved render inputs before hashing.
static func signature(records: Array) -> String:
	var rows: Array = []
	# Fixture shape changes Spot count and offsets, even when energy is unchanged.
	var fields := ["scene", "x", "y", "z", "rotation_x", "rotation_y", "rotation_z", "scale_x", "scale_y", "scale_z", "light_energy", "light_angle", "energy_multiplier", "light_color", "fixture_shape", "flicker_mode", "flicker_step", "blood_texture", "blood_surface", "blood_normal", "blood_attachment"]
	for record: Dictionary in records:
		var row: Array = []
		for field in fields:
			row.append(_canonical(record.get(field)))
		rows.append(row)
	return JSON.stringify(rows).sha256_text()


static func _canonical(value: Variant) -> Variant:
	if value is float or value is int:
		var number := String.num(float(value), 4)
		# JSON writes IEEE -0.0 as 0.0; both describe the same render input.
		return "0.0" if number == "-0.0" else number
	if value is Array:
		var result: Array = []
		for child: Variant in value: result.append(_canonical(child))
		return result
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var result := {}
		for key: Variant in keys: result[key] = _canonical(value[key])
		return result
	return value
