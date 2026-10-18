extends RefCounted
## Authored settings are persisted; gameplay pixels are transient.
const CONFIG := preload("res://game/presentation/office_floor/public/surface_decal_config.gd")

static func floor_for(session: Variant) -> Node3D:
	if session is Node:
		var host: Variant = session.get("host")
		if host is Node:
			var floor_view := host.get_node_or_null("Floor") as Node3D
			if floor_view != null and floor_view.has_method("configure_surface_decals"): return floor_view
	return null

static func capture(session: Variant) -> Dictionary:
	var floor_view := floor_for(session)
	return floor_view.call("get_surface_decals") if floor_view != null else {}

static func restore(session: Variant, raw: Dictionary) -> void:
	var floor_view := floor_for(session)
	if floor_view != null:
		floor_view.call("configure_surface_decals", raw)
		var root: Variant = session.get("root")
		if root is Node: root.set_meta("surface_decals_v1", floor_view.call("get_surface_decals"))
