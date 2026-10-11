extends SceneTree
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
var failures := 0
var _had_save := false
var _save := PackedByteArray()
const SAVE := "user://planned_layout.json"
const BASE := "res://game/presentation/office_floor/public/base_office_map.json"

func _initialize() -> void:
	root.size = Vector2i(320, 180)
	call_deferred("_run")

func _run() -> void:
	_had_save = FileAccess.file_exists(SAVE)
	if _had_save:
		_save = FileAccess.get_file_as_bytes(SAVE)
	var file := FileAccess.open(SAVE, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(BASE))
	file.close()
	var menu := FRONT.instantiate()
	root.add_child(menu)
	current_scene = menu
	menu.call("_action", "start")
	var deadline := Time.get_ticks_msec() + 120000
	while current_scene == menu and Time.get_ticks_msec() < deadline:
		await process_frame
	var stage := current_scene
	if stage == menu:
		_finish(1, "mission start timed out")
		return
	for frame in 30:
		await process_frame
	var planner: Node = stage.get("planning_mode")
	var objects: Object = planner.get("objects")
	var storage: Object = planner.get("storage")
	var before: Array = objects.get("placed").duplicate()
	var furniture: Array[Node3D] = []
	for node: Node3D in before:
		if is_instance_valid(node) and not node.has_meta("planning_actor_kind") and not node.has_meta("planning_existing"):
			furniture.append(node)
	if furniture.size() < 100:
		_finish(1, "too few placed furniture nodes: %d" % furniture.size())
		return
	# Gameplay aftermath: one prop pushed, one removed.
	var moved := furniture[0]
	moved.position += Vector3(1.0, 0.0, 0.0)
	furniture[1].free()
	var allocator_before := OS.get_static_memory_usage()
	var changed: bool = storage.call("restore_authored")
	var allocator_after := OS.get_static_memory_usage()
	print("Planner restore allocator MiB: %.2f -> %.2f" % [allocator_before / 1048576.0, allocator_after / 1048576.0])
	var survivors := 0
	for node in furniture:
		survivors += 1 if is_instance_valid(node) else 0

	print("Planner restore kept %d of %d furniture nodes" % [survivors, furniture.size()])
	var failures := 0
	if not changed:
		failures += 1
		push_error("Restore must detect the changed map")
	if survivors < furniture.size() * 3 / 4:
		failures += 1
		push_error("Restore rebuilt untouched furniture instead of reusing it")
	if is_instance_valid(moved):
		failures += 1
		push_error("Moved prop must be rebuilt at its authored place")
	if allocator_after - allocator_before > 128 * 1048576:
		failures += 1
		push_error("Restore grew the allocator by more than 128 MiB")
	var placed_count: int = (objects.get("placed") as Array).size()
	if placed_count < before.size() - 2:
		failures += 1
		push_error("Restore lost objects: %d of %d" % [placed_count, before.size()])
	_finish(failures, "")

func _finish(failures: int, message: String) -> void:
	if not message.is_empty():
		push_error(message)
	if _had_save:
		var file := FileAccess.open(SAVE, FileAccess.WRITE)
		file.store_buffer(_save)
		file.close()
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("Smooth planner restore failures: ", failures)
	quit(failures)
