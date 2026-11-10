extends SceneTree
## Every way into play (menu, restart, leaving the planner) reaches the same scene state through PLAY_PREP.
const PREP := preload("res://game/bootstrap/app/play_scene_prep.gd")
const MERGE := preload("res://game/bootstrap/app/planning_static_merge.gd")
const TRIM := preload("res://game/bootstrap/app/planning_prop_trim.gd")
const QUALITY := preload("res://game/core/vfx/public/effects_quality.gd")
const WALL := "res://game/presentation/office_floor/public/structural/wall_straight.tscn"
const MOUSE := "res://models/objects/enviroments/05/05_computer_mouse.glb"
var failures := 0


func _initialize() -> void:
	QUALITY.set_level(QUALITY.LOW)
	var world := Node3D.new()
	root.add_child(world)
	var placed: Array = []
	for i in 2:
		var wall := (load(WALL) as PackedScene).instantiate() as Node3D
		world.add_child(wall)
		wall.position = Vector3(i * 2.0, 0, 1)
		wall.set_meta("planning_scene_path", WALL)
		placed.append(wall)
	var decor := Node3D.new()
	world.add_child(decor)
	TRIM.tag(decor, {}, MOUSE)
	await process_frame
	Engine.set_meta("planning_active", true) # The planner open: everything shows, nothing merged.
	TRIM.apply_live(self)
	_check(decor.visible, "the planner shows trimmed decor")
	Engine.set_meta("planning_active", false)
	PREP.apply(placed, world)
	var first := _state()
	_check(first[0] > 0 and first[1] == 1, "play merges structure and trims decor: %s" % [first])
	PREP.apply(placed, world)
	_check(_state() == first, "a second call changes nothing")
	Engine.set_meta("planning_active", true)
	MERGE.restore(self)
	TRIM.apply_live(self)
	Engine.set_meta("planning_active", false)
	PREP.apply(placed, world)
	await process_frame
	_check(_state() == first, "leaving the planner again reaches the same state")
	QUALITY.set_level(QUALITY.HIGH)
	print("Play scene prep tests: %d failure(s)" % failures)
	quit(failures)


func _state() -> Array:
	var merged := 0
	for holder in get_nodes_in_group(MERGE.GROUP):
		if not holder.is_queued_for_deletion():
			merged += (holder.get_meta(MERGE.SOURCES, []) as Array).size()
	return [merged, get_nodes_in_group(TRIM.GROUP).filter(func(n): return not n.visible).size()]


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
