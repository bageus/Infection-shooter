extends SceneTree

const FLOOR_SIZE := preload("res://game/bootstrap/app/planning_floor_size.gd")
const MAIN := preload("res://game/bootstrap/app/main.tscn")
var _failures := 0


func _initialize() -> void:
	_check(FLOOR_SIZE.valid([120.0, 40.0]), "A size inside the limits is valid")
	_check(not FLOOR_SIZE.valid([5.0, 40.0]) and not FLOOR_SIZE.valid([120.0, 900.0]), "Sizes outside the limits are refused")
	_check(not FLOOR_SIZE.valid([]) and not FLOOR_SIZE.valid(["wide", 40.0]), "Malformed sizes are refused")
	call_deferred("_run_planner_flow")


## A saved size resizes the floor and its collision; a map without one restores the default.
func _run_planner_flow() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	await physics_frame
	stage.call("_on_planning_pressed")
	var planner: Node = stage.get("planning_mode")
	var floor_view := stage.get_node("Floor") as Node3D
	var collision := stage.get_node("FloorBody/CollisionShape3D") as CollisionShape3D
	FLOOR_SIZE.restore(planner, [120.0, 40.0])
	_check(floor_view.get("floor_size") == Vector2(120.0, 40.0), "The floor takes the saved size")
	_check((collision.shape as BoxShape3D).size.x == 120.0 and (collision.shape as BoxShape3D).size.z == 40.0, "The collision follows the saved size")
	_check(FLOOR_SIZE.capture(planner) == [120.0, 40.0], "The size is captured back from the floor")
	FLOOR_SIZE.restore(planner, [])
	_check(floor_view.get("floor_size") == FLOOR_SIZE.DEFAULT_SIZE, "A map without a size restores the default")
	_check((collision.shape as BoxShape3D).size.x == FLOOR_SIZE.DEFAULT_SIZE.x, "The collision returns to the default size")
	stage.queue_free()
	await process_frame
	if _failures == 0:
		print("Floor size tests passed")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAILED: " + message)
		print("FAILED: " + message)
