extends SceneTree
## Planner door lock setting: layout restore, map validation and the elevator exclusion.
const PLANNER_DOOR := preload("res://game/bootstrap/app/planning_door_options.gd")
const LAYOUT_PROPERTIES := preload("res://game/bootstrap/app/planning_layout_properties.gd")
const LAYOUT_VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
const EMERGENCY_DOOR := preload("res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn")
const ELEVATOR_DOOR := preload("res://game/presentation/office_floor/public/structural/elevator_door.tscn")
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Emergency door scene starts key-locked; the layout record overrides it.
	var wall := EMERGENCY_DOOR.instantiate() as Node3D
	root.add_child(wall)
	var door := PLANNER_DOOR.lockable_controller(wall)
	_expect(door != null and door.get_lock_state() == &"key", "Emergency door scene is key-locked by default")
	LAYOUT_PROPERTIES.restore(wall, {"door_lock": "sealed"})
	_expect(door.get_lock_state() == &"sealed", "Layout restore applies a sealed door")
	LAYOUT_PROPERTIES.restore(wall, {"door_lock": "open"})
	_expect(door.get_lock_state() == &"open", "Layout restore applies an open door")
	LAYOUT_PROPERTIES.restore(wall, {})
	_expect(door.get_lock_state() == &"open", "Records without door_lock leave the door as restored")
	LAYOUT_PROPERTIES.restore(wall, {"door_one_way": true})
	_expect(PLANNER_DOOR.is_one_way(door), "Layout restore applies a one-way door")
	LAYOUT_PROPERTIES.restore(wall, {})
	_expect(not PLANNER_DOOR.is_one_way(door), "Records without door_one_way open both ways")
	var bad_way := {"objects": [{"scene": "res://x.tscn", "door_one_way": "yes"}]}
	_expect(LAYOUT_VALIDATOR.error(bad_way) != "", "Validator rejects a non-bool door_one_way")
	var bad := {"objects": [{"scene": "res://x.tscn", "door_lock": "bogus"}]}
	_expect(LAYOUT_VALIDATOR.error(bad) != "", "Validator rejects an unknown door_lock")
	var good := {"objects": [{"scene": "res://x.tscn", "door_lock": "sealed"}]}
	_expect(LAYOUT_VALIDATOR.error(good) == "", "Validator accepts a sealed door_lock")
	wall.queue_free()
	# Elevators are not part of the setting.
	var elevator := ELEVATOR_DOOR.instantiate() as Node3D
	root.add_child(elevator)
	_expect(PLANNER_DOOR.lockable_controller(elevator) == null, "Elevator door has no planner lock setting")
	elevator.queue_free()
	await process_frame
	print("Planner door lock tests: %d failure(s)." % failures)
	quit(failures)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
