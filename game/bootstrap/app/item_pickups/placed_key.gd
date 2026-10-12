extends "res://game/bootstrap/app/mission_key.gd"
## The emergency key as a planner item. The tree is paused while planning, so the
## first frame is the first game frame: hover 25 cm over the planned surface from there
## (the planned position itself stays on the surface).

var _anchored := false


func _process(delta: float) -> void:
	if not _anchored:
		_anchored = true
		set("_base_y", global_position.y + 0.25)
	super._process(delta)
