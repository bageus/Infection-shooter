extends SceneTree

const FLOOR_HINT := preload("res://game/bootstrap/app/floor_hint_guide.gd")
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

	print("Floor hint tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


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
