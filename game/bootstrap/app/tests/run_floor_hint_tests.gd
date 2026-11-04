extends SceneTree

const FLOOR_HINT := preload("res://game/bootstrap/app/floor_hint_guide.gd")
const FLOOR_ROUTE := preload("res://game/bootstrap/app/floor_route.gd")
const FLOOR_Y := 0.04
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := Node3D.new()
	root.add_child(player)
	# A dictionary is shared by reference, so the lambda sees the goal as the test changes it.
	var state := {"goal": Vector3(10.0, 0.0, 0.0)}
	var guide: Node3D = FLOOR_HINT.new()
	guide.player = player
	guide.target_source = func() -> Vector3: return state.goal
	root.add_child(guide)

	guide.call("_process", 0.016)
	var shown := _visible_chevrons(guide)
	_check(shown.size() > 0, "a goal ahead shows chevrons")
	_check(shown.all(func(chevron: MeshInstance3D) -> bool: return chevron.global_position.x > 0.0 and chevron.global_position.x < 10.0), "chevrons lie between the player and the goal")
	_check(shown.all(func(chevron: MeshInstance3D) -> bool: return is_equal_approx(chevron.global_position.y, FLOOR_Y)), "chevrons stay on the floor")

	state.goal = Vector3.INF
	guide.call("_process", 0.016)
	_check(_visible_chevrons(guide).is_empty(), "no goal hides chevrons")

	state.goal = Vector3(1.0, 0.0, 0.0)
	guide.call("_process", 0.016)
	_check(_visible_chevrons(guide).is_empty(), "a goal inside the clearance hides chevrons")

	state.goal = Vector3(10.0, 0.0, 0.0)
	guide.call("set_hints_enabled", false)
	_check(not guide.visible and not guide.is_processing(), "turning hints off hides and stops the guide")
	guide.call("set_hints_enabled", true)
	_check(guide.visible and guide.is_processing(), "turning hints on restores the guide")

	await _wall_route(guide, player, state)

	print("Floor hint tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


# A wall across the straight line makes the trail detour around it instead of pointing into it.
func _wall_route(guide: Node3D, player: Node3D, state: Dictionary) -> void:
	var wall := StaticBody3D.new()
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 2.0, 8.0)
	box.shape = shape
	wall.add_child(box)
	wall.position = Vector3(5.0, 1.0, 0.0)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	state.goal = Vector3(10.0, 0.0, 0.0)
	guide.set("_route", FLOOR_ROUTE.new()) # drops the cell answers cached before the wall existed
	guide.set("_route_age", 99.0)
	guide.call("_process", 0.016)
	var waypoints: Array = guide.get("_waypoints")
	_check(waypoints.size() > 1, "a wall on the way adds route bends")
	_check(waypoints.any(func(point: Vector3) -> bool: return absf(point.z) > 4.0), "the route goes around the wall end")
	_check(waypoints[-1].distance_to(state.goal) < 0.1, "the route ends at the goal")
	state.goal = Vector3(5.0, 0.0, 30.0) # beyond the wall's end and far: a way still leads toward it
	guide.set("_route", FLOOR_ROUTE.new())
	guide.set("_route_age", 99.0)
	guide.call("_process", 0.016)
	_check((guide.get("_waypoints") as Array).size() > 0, "a far goal still gets a route")


func _visible_chevrons(guide: Node3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child in guide.get_children():
		var chevron := child as MeshInstance3D
		if chevron != null and chevron.visible:
			found.append(chevron)
	return found


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
