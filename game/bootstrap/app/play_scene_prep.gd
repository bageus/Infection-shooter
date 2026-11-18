extends RefCounted
## The one way every entry into play (menu start, restart, level travel, leaving the planner) readies the scene
## for rendering: small decor trimmed by quality (structure is not merged, see apply). Safe to call twice.
const PROP_TRIM := preload("res://game/bootstrap/app/planning_prop_trim.gd")


static func apply(_placed: Array, host: Node3D) -> void:
	# Wall merging is off: merged meshes hide the originals that take wall decals, so damage never showed.
	# The merge helper stays for a future merge that keeps decals.
	PROP_TRIM.apply_live(host.get_tree())
