extends SceneTree
## The fire door's leaf is solid when it stands open: its mesh is named DoorHandle, but it is the whole panel.
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var door := (load("res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(door)
	var controller := door.get_node("DoorController")
	controller.configure_player(door)
	controller.set("_open_amount", 1.0)
	for i in 4:
		await physics_frame
	var leaf_shapes: Array[CollisionShape3D] = []
	for body in door.find_children("MovingDoorBody", "StaticBody3D", true, false):
		for shape in body.get_children():
			if shape is CollisionShape3D:
				leaf_shapes.append(shape)
	_check(not leaf_shapes.is_empty(), "the fire door leaf has collision shapes")
	for shape in leaf_shapes:
		_check(not shape.disabled, "the open fire door panel keeps its collision")
	door.free()
	print("Fire door leaf tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
