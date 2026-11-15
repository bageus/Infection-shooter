extends SceneTree
## The floor sill of a door frame has no collision (a character body cannot step up), the frame's sides still have.
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for file in ["metal_door", "lab_glass_door"]:
		var door := (load("res://game/presentation/office_floor/public/structural/%s.tscn" % file) as PackedScene).instantiate() as Node3D
		root.add_child(door)
		for i in 10:
			await physics_frame
		var space := root.get_world_3d().direct_space_state
		var blocked := false
		for height in [0.03, 0.08, 0.13]:
			var across := PhysicsRayQueryParameters3D.create(Vector3(0, height, -2), Vector3(0, height, 2), 1)
			blocked = blocked or not space.intersect_ray(across).is_empty()
		_check(not blocked, "%s: nothing at foot height crosses the opening" % file)
		var along := PhysicsRayQueryParameters3D.create(Vector3(-2, 0.08, 0), Vector3(2, 0.08, 0), 1)
		_check(not space.intersect_ray(along).is_empty(), "%s: the frame beside the opening is still solid at the floor" % file)
		door.free()
		await physics_frame
	print("Door sill tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
