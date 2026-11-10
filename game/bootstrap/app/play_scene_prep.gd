extends RefCounted
## The one way every entry into play (menu start, restart, level travel, leaving the planner) readies the scene
## for rendering: fixed structure merged, small decor trimmed by quality. Safe to call twice.
const STATIC_MERGE := preload("res://game/bootstrap/app/planning_static_merge.gd")
const PROP_TRIM := preload("res://game/bootstrap/app/planning_prop_trim.gd")


static func apply(placed: Array, host: Node3D) -> void:
	STATIC_MERGE.merge(placed, host)
	PROP_TRIM.apply_live(host.get_tree())
