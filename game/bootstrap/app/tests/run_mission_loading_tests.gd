extends SceneTree
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
const ASSET := "res://game/bootstrap/app/tests/fixtures/layout_object.tscn"
const SAVE := "user://planned_layout.json"
var failures := 0
var _had_save := false
var _saved_bytes := PackedByteArray()
var _had_backup := false
var _backup_bytes := PackedByteArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_had_save = FileAccess.file_exists(SAVE)
	if _had_save:
		_saved_bytes = FileAccess.get_file_as_bytes(SAVE)
	_had_backup = FileAccess.file_exists(SAVE + ".bak")
	if _had_backup:
		_backup_bytes = FileAccess.get_file_as_bytes(SAVE + ".bak")
		DirAccess.remove_absolute(SAVE + ".bak")
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
	_expect(loader.get("_choices") != null and (loader.get("_choices") as VBoxContainer).get_child_count() == 1, "Corrupt save offers the valid shipped map")
	_expect("objects must be an array" in str((loader.get("label") as Label).text), "Recovery UI explains schema corruption")
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
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Mission startup leaves the aiming cursor free")
	var planner: Node = stage.get("planning_mode")
	_expect(planner.get("storage").get("authored_layout").get("objects").size() == 64, "All map records are committed before activation")
	var backup := FileAccess.open(SAVE + ".bak", FileAccess.WRITE)
	backup.store_string(JSON.stringify({"version": 8, "objects": records}))
	backup.close()
	_write('{"objects":null}')
	stage.call("_on_restart_pressed")
	var failure: Node = root.find_children("*", "CanvasLayer", true, false).filter(func(node: Node) -> bool: return node.get_script() != null and not node.is_queued_for_deletion() and node.get_script().resource_path.ends_with("mission_loader.gd"))[0]
	await _wait(func() -> bool: return (failure.get("back") as Button).visible)
	_expect(not is_instance_valid(stage), "Restart releases the previous mission before loading the next one")
	_expect(current_scene == null and failure.get_parent() == root, "Failed restart keeps only the loader error screen")
	failure.call("_close_error")
	await _wait(func() -> bool: return current_scene != null and current_scene.scene_file_path.ends_with("front_end.tscn"))
	_expect(not paused, "Failed restart returns to the menu unpaused")
	_write(JSON.stringify({"version": 8, "objects": records}))
	current_scene.call("_action", "start")
	await _wait(func() -> bool: return current_scene != null and current_scene.scene_file_path == "res://game/bootstrap/app/main.tscn")
	stage = current_scene
	await process_frame
	var before_id := stage.get_instance_id()
	stage.call("_on_restart_pressed")
	stage.call("_on_restart_pressed")
	await process_frame
	_expect(paused, "Restart pauses gameplay while loading")
	await _wait(func() -> bool: return current_scene != null and current_scene.get_instance_id() != before_id)
	_expect(current_scene.get_instance_id() != before_id and not paused, "Restart completes via the same asynchronous pipeline")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Restart leaves the aiming cursor free")
	await process_frame
	_expect(not is_instance_valid(instance_from_id(before_id)), "Successful restart releases the previous mission")
	current_scene.queue_free()
	await process_frame
	# Corrupt JSON must not block a deliberate backup start, or rewrite evidence.
	var recovery_menu := FRONT.instantiate()
	root.add_child(recovery_menu)
	current_scene = recovery_menu
	_write("{interrupted")
	recovery_menu.call("_action", "start")
	var recovery_loader: Node = recovery_menu.find_children("*", "CanvasLayer", true, false)[0]
	await _wait(func() -> bool: return (recovery_loader.get("back") as Button).visible)
	_expect((recovery_loader.get("_choices") as VBoxContainer).get_child_count() == 2, "Recovery offers both valid backup and shipped map")
	(recovery_loader.get("_choices") as VBoxContainer).get_child(0).emit_signal("pressed")
	(recovery_loader.get("_choices") as VBoxContainer).get_child(0).emit_signal("pressed")
	await _wait(func() -> bool: return current_scene != recovery_menu)
	_expect(current_scene.get("planning_mode").get("storage").authored_layout.objects.size() == 64, "Selecting backup activates its full map")
	_expect(FileAccess.get_file_as_string(SAVE) == "{interrupted", "Backup launch does not overwrite the corrupt save")
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
	if _had_backup:
		var backup := FileAccess.open(SAVE + ".bak", FileAccess.WRITE)
		backup.store_buffer(_backup_bytes)
		backup.close()
	else:
		DirAccess.remove_absolute(SAVE + ".bak")
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
