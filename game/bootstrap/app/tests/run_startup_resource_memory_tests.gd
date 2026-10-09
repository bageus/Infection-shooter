extends SceneTree
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
var failures := 0
var peak_memory := 0
var peak_rss := 0
var peak_video := 0
var _had_save := false
var _save := PackedByteArray()
const SAVE := "user://planned_layout.json"
const BASE := "res://game/presentation/office_floor/public/base_office_map.json"
const ALLOCATOR_LIMIT := 1280 * 1024 * 1024

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
	var started := Time.get_ticks_msec()
	menu.call("_action", "start")
	await _wait(menu)
	if current_scene == menu:
		_restore_save()
		quit(1)
		return
	print("Full map startup msec: ", Time.get_ticks_msec() - started)
	_check()
	var stage := current_scene
	started = Time.get_ticks_msec()
	stage.call("_on_restart_pressed")
	await _wait(stage)
	if current_scene == stage:
		_restore_save()
		quit(1)
		return
	print("Full map restart msec: ", Time.get_ticks_msec() - started)
	_check()
	for frame in 180:
		await process_frame
	current_scene.queue_free()
	await process_frame
	await process_frame
	print("Full map peak allocator MiB: ", float(peak_memory) / 1048576.0)
	print("Full map peak RSS MiB: ", float(peak_rss) / 1048576.0)
	print("Full map peak video MiB: ", float(peak_video) / 1048576.0)
	if DisplayServer.get_name() == "headless" and peak_memory > ALLOCATOR_LIMIT:
		failures += 1
		push_error("Startup resources exceeded the 1280 MiB allocator budget")
	_restore_save()
	print("Full map startup/restart failures: ", failures)
	quit(failures)

func _wait(previous: Node) -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while current_scene == previous and Time.get_ticks_msec() < deadline:
		peak_memory = maxi(peak_memory, OS.get_static_memory_usage())
		peak_video = maxi(peak_video, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
		if OS.get_name() == "Linux":
			var status := FileAccess.open("/proc/self/status", FileAccess.READ)
			if status != null:
				for line_index in 128:
					var line := status.get_line()
					if line.begins_with("VmRSS:"):
						peak_rss = maxi(peak_rss, int(line.trim_prefix("VmRSS:").strip_edges().get_slice(" ", 0)) * 1024)
						break
		await process_frame
	if current_scene == previous:
		failures += 1
		push_error("Full map timed out")

func _check() -> void:
	var planner: Node = current_scene.get("planning_mode")
	var placed: Array = planner.get("objects").get("placed")
	print("Full map placed: ", placed.size())
	var authored: Dictionary = planner.get("storage").get("authored_layout")
	if placed.size() < 1033 or authored["objects"].size() != 1034:
		failures += 1
		push_error("Full map object count changed")
	var furniture := 0
	for node: Node in placed:
		if not node is RigidBody3D or node.get("_geometry") == null:
			continue
		furniture += 1
		if node.get("_shapes").is_empty() and not "01_floor_" in str(node.get("model_path")):
			failures += 1
			push_error("Furniture lacks collision: " + str(node.get("model_path")))
	print("Full map furniture checked: ", furniture)


func _restore_save() -> void:
	if _had_save:
		var file := FileAccess.open(SAVE, FileAccess.WRITE)
		file.store_buffer(_save)
		file.close()
	else:
		DirAccess.remove_absolute(SAVE)
