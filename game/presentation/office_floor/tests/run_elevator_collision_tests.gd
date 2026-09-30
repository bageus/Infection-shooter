extends SceneTree

const DOOR := preload("res://game/presentation/office_floor/public/structural/elevator_door.tscn")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var door := DOOR.instantiate() as Node3D
	door.name = "ElevatorDoor2"
	door.position = Vector3(7, 0, -4)
	door.rotation.y = 0.65
	door.scale = Vector3(1.3, 1.0, 1.3)
	stage.add_child(door)
	await process_frame
	await physics_frame
	await physics_frame
	var body := door.get_node("Body") as StaticBody3D
	_check(body.get_child_count() > 0, "Renamed elevator builds wall collision")
	for x in [-1.53, 1.53]:
		var hit := _ray(door, Vector3(x, 1.2, -1), Vector3(x, 1.2, 1))
		_check(hit.get("collider") == body, "Visible side wall blocks passage")
	# Moving leaves may block a closed doorway; its static shell must not.
	var opening := _ray(door, Vector3(0, 1.2, -1), Vector3(0, 1.2, 1))
	_check(opening.get("collider") != body, "Shell preserves the doorway")
	stage.queue_free()
	await process_frame
	if _failures == 0:
		print("Elevator collision tests passed")
	quit(0 if _failures == 0 else 1)


func _ray(door: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(door.to_global(from), door.to_global(to))
	return door.get_world_3d().direct_space_state.intersect_ray(query)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
