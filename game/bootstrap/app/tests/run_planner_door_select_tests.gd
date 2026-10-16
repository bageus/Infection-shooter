extends SceneTree
## With a door still active in the palette, a plain click on an installed door selects it
## and opens its settings instead of placing another door.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const DOOR_PATH := "res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn"
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var planner: Node = stage.get("planning_mode")
	planner.enter()
	# The authored map can fill every nearby pick ray. Keep this input regression
	# independent of furniture layout while using the real camera and door geometry.
	planner.camera.global_position += Vector3(1000, 1000, 1000)
	var objects: Node = planner.objects
	var door := (load(DOOR_PATH) as PackedScene).instantiate() as Node3D
	planner.root.add_child(door)
	objects.placed.append(door)
	# Park the door where nothing else (player, furniture) shares its screen pixel.
	var clear := false
	var visible_area := Rect2(Vector2(420, 60), root.get_visible_rect().size - Vector2(460, 120))
	for step in 24:
		var side := 1.0 if step % 2 == 0 else -1.0
		door.global_position = planner.camera.global_position + (-planner.camera.global_transform.basis.z) * 8.0 + planner.camera.global_transform.basis.x * side * (1.0 + step * 0.6)
		var at: Vector2 = planner.camera.unproject_position(door.global_position)
		if visible_area.has_point(at) and planner.geometry._planned_object_at(at) == door:
			clear = true
			break
	_check(clear, "The test door can be picked on its own")
	objects.selected_path = DOOR_PATH
	objects.selected_entry = {"path": DOOR_PATH, "name": "Door"}
	objects._rebuild_preview()
	_check(objects.preview != null and objects.selected == null, "A door is active in the palette")
	var count: int = objects.placed.size()
	var screen: Vector2 = planner.camera.unproject_position(door.global_position)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = screen
		event.global_position = screen
		# The planner's own input handler, so a headless window's stretch cannot move the click.
		planner._input(event)
		await process_frame
	_check(objects.placed.size() == count, "Clicking an installed door places nothing")
	_check(objects.selected == door, "Clicking an installed door selects it")
	_check(planner.controls.door_options.panel.visible, "The door settings open for the installed door")
	planner.exit()
	stage.queue_free()
	await process_frame
	print("Planner door select tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
