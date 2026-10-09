extends SceneTree
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
const ASSET := "res://game/bootstrap/app/tests/fixtures/layout_object.tscn"
const SAVE := "user://planned_layout.json"
var failures := 0
var _had_save := false
var _saved_bytes := PackedByteArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_had_save = FileAccess.file_exists(SAVE)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SAVE)
	_write('{"objects":"damaged"}')
	var frontend := FRONT.instantiate()
	root.add_child(frontend)
	current_scene = frontend
	frontend.call("_action", "start")
	frontend.call("_action", "start")
	_expect(current_scene == frontend, "Start keeps the menu until the mission is ready")
	var loaders := frontend.find_children("*", "CanvasLayer", true, false)
	_expect(loaders.size() == 1, "Repeated start creates only one loader")
	var loader: Node = loaders[0]
	_expect((loader.get("label") as Label).is_visible_in_tree(), "Loading UI is visible before resource work")
	await _wait(func() -> bool: return is_instance_valid(loader) and (loader.get("back") as Button).visible)
	_expect(current_scene == frontend and is_instance_valid(frontend) and not paused, "Invalid map preserves the previous menu and pause state")
	_expect(loader.get("pending") == null, "Failed pending mission is released")
	loader.call("_close_error")
	await process_frame
	_expect(not frontend.get("_loading"), "Error dismissal permits retry")
	var records: Array = []
	for index in 64:
		records.append({"scene": ASSET, "x": index, "object_id": "load_%d" % index})
	_write(JSON.stringify({"version": 8, "objects": records}))
	var first_frame := Engine.get_process_frames()
	frontend.call("_action", "start")
	await _wait(func() -> bool: return current_scene != frontend)
	var stage := current_scene
	_expect(is_instance_valid(stage) and stage.scene_file_path == "res://game/bootstrap/app/main.tscn", "Retry activates the completed mission")
	_expect(Engine.get_process_frames() - first_frame >= 8, "Frames continue during resource preparation and object creation")
	_expect(not paused, "Gameplay resumes only after startup")
	var planner: Node = stage.get("planning_mode")
	_expect(planner.get("storage").get("authored_layout").get("objects").size() == 64, "All map records are committed before activation")
	var camera := root.get_camera_3d()
	_write('{"objects":null}')
	stage.call("_on_restart_pressed")
	var failure: Node = stage.find_children("*", "CanvasLayer", true, false).filter(func(node: Node) -> bool: return node.get_script() != null and node.get_script().resource_path.ends_with("mission_loader.gd"))[0]
	await _wait(func() -> bool: return (failure.get("back") as Button).visible)
	_expect(current_scene == stage and root.get_camera_3d() == camera, "Failed restart preserves the previous mission and camera")
	_expect(stage.visible, "Failed restart restores the previous mission visuals")
	failure.call("_close_error")
	await process_frame
	_write(JSON.stringify({"version": 8, "objects": records}))
	var before := stage
	stage.call("_on_restart_pressed")
	stage.call("_on_restart_pressed")
	_expect(current_scene == before and paused, "Restart also retains and pauses the previous mission while loading")
	_expect(not before.visible, "Restart suspends old floor rendering behind the loading overlay")
	await _wait(func() -> bool: return current_scene != before)
	_expect(current_scene != before and not paused, "Restart completes via the same asynchronous pipeline")
	await process_frame
	_expect(not is_instance_valid(before), "Successful restart releases the previous mission")
	current_scene.queue_free()
	await process_frame
	_restore_save()
	print("Mission loading tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _wait(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(condition.call(), "Mission transition completes within timeout")


func _write(text: String) -> void:
	var file := FileAccess.open(SAVE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _restore_save() -> void:
	if _had_save:
		var file := FileAccess.open(SAVE, FileAccess.WRITE)
		file.store_buffer(_saved_bytes)
		file.close()
	else:
		DirAccess.remove_absolute(SAVE)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
