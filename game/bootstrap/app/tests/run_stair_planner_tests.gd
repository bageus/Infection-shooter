extends SceneTree
## O01: real layout load/edit/delete/undo and pause/resume refresh the stair cache.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const LAYOUT := preload("res://game/bootstrap/app/mission_layout.gd")
const PATH := "res://models/objects/enviroments/01/01_stairs.glb"
var failures := 0
var app: Node3D
var planner: Node
var objects: Node
var mission: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = MAIN.instantiate()
	root.add_child(app)
	current_scene = app
	(app.get("player") as Node).set_physics_process(false)
	planner = app.get("planning_mode")
	objects = planner.get("objects")
	mission = app.get("mission_layout")
	planner.call("enter")
	var result: Dictionary = objects.call("_apply_layout_data", {"version": 8, "objects": [
		{"scene": PATH, "x": 0, "y": -3, "z": 0},
		{"scene": PATH.replace("01_stairs.glb", "01_stairs_2.glb"), "x": 12, "y": -3, "z": 2},
	]})
	_check(not result.has("error"), "Real loader accepts canonical and legacy stair records")
	planner.call("exit")
	await _settle()
	_check(not (mission.get("_openings") as Array).is_empty(), "Loaded stairs create floor openings after resume")
	_equivalent("Loaded layout")
	await _edits_and_undo()
	var storage: RefCounted = planner.get("storage")
	var saved: Dictionary = storage.call("_collect_layout_data")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(saved))
	result = objects.call("_apply_layout_data", roundtrip)
	_check(not result.has("error"), "Actual layout snapshot reload succeeds")
	await _settle()
	_equivalent("Snapshot roundtrip")
	objects.call("clear_layout")
	await _settle()
	_check((mission.get("_openings") as Array).is_empty(), "Clear layout clears every exit opening")
	_check(not mission.is_processing(), "Empty real map disables layout polling")
	_check(not (app.get_node("FloorBody/CollisionShape3D") as CollisionShape3D).disabled, "Clear restores the original solid floor")
	app.queue_free()
	await process_frame
	await process_frame
	print("Stair planner tests: %d failures" % failures)
	quit(1 if failures else 0)


func _edits_and_undo() -> void:
	planner.call("enter")
	var placed: Array = objects.get("placed")
	var stair := placed.filter(func(n: Node) -> bool: return str(n.get_meta("planning_scene_path", "")).get_file() == "01_stairs.glb")[0] as Node3D
	objects.call("_select", stair)
	objects.call("_rotate_selected", 90.0)
	objects.call("_scale_selected", Vector3.ONE * .1)
	objects.call("_nudge_selected", Vector2.RIGHT)
	var history: RefCounted = planner.get("edit_history")
	history.call("undo")
	objects.call("_delete_selected")
	await process_frame
	await process_frame
	history.call("undo") # Recreates a new root, rather than reusing the deleted instance.
	planner.call("exit")
	await _settle()
	_equivalent("Rotate/scale/nudge/undo/delete/undo")


func _settle() -> void:
	await create_timer(.45).timeout
	await physics_frame
	await process_frame


func _equivalent(label: String) -> void:
	var oracle := LAYOUT.new()
	var expected: Array[Rect2] = []
	for stair in app.get_node("PlanningObjects").get_children():
		if not stair is Node3D or str(stair.get_meta("planning_scene_path", "")).get_file() not in ["01_stairs.glb", "01_stairs_2.glb"]:
			continue
		var bounds: AABB = oracle.call("_visual_bounds", stair)
		if bounds.size.length_squared() >= .01 and bounds.position.y <= -.4 and bounds.end.y >= -.05:
			expected.append_array(oracle.call("_stair_openings", stair, bounds))
	_check(mission.get("_openings") == expected, label + ": openings match the full-scan reference")
	for opening in expected:
		var center := opening.get_center()
		_check(mission.call("goal_reached", Vector3(center.x, -2, center.y)), label + ": opening stays an exit")
	oracle.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
