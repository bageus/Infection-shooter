extends SceneTree
## Manual A/B harness; --sync runs the original named-map route. Not a CI budget.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const MAP := "res://game/presentation/office_floor/public/base_office_map.json"
var samples: Array[float] = []
var observing := false
var last_usec := 0
var peak_memory := 0
var peak_rss := 0
var spikes: Array[Dictionary] = []
var planner: Node

class ObservedCatalog extends CATALOG:
	var sample: Callable
	func _create_asset(path: String) -> Node3D:
		var result := super._create_asset(path)
		sample.call()
		return result


func _initialize() -> void:
	process_frame.connect(_sample_frame)
	call_deferred("_run")


func _run() -> void:
	var fixture := _fixture()
	var stage: Node = fixture.stage
	var storage: Variant = fixture.storage
	var catalog: ObservedCatalog = fixture.catalog
	var path: String = fixture.path
	for index in 5:
		await process_frame
	var baseline := OS.get_static_memory_usage()
	peak_memory = baseline
	peak_rss = 0
	observing = true
	last_usec = Time.get_ticks_usec()
	var started := last_usec
	var sync := "--sync" in OS.get_cmdline_user_args()
	print("PROFILE_BEGIN ", "sync" if sync else "staged")
	if sync:
		# Original load_named_map body, including read/validation and snapshot.
		var report: Dictionary = storage._load_layout_from_path(path)
		if report.has("error"):
			push_error(str(report.error))
		storage.map_name_edit.text = "profile_named_map"
		storage.snapshot_authored()
	else:
		await storage.load_named_map("profile_named_map")
	var elapsed := Time.get_ticks_usec() - started
	_memory()
	await process_frame
	observing = false
	samples.sort()
	_report(sync, elapsed, baseline, storage.authored_layout.objects.size())
	DirAccess.remove_absolute(path)
	catalog.bind_asset = Callable()
	catalog.sample = Callable()
	stage.queue_free()
	await process_frame
	quit()


func _fixture() -> Dictionary:
	var stage := MAIN.instantiate()
	stage.set("defer_layout_loading", true)
	root.add_child(stage)
	current_scene = stage
	paused = true
	planner = stage.get("planning_mode")
	var storage: Variant = planner.get("storage")
	storage._load_layout_from_path(MAP)
	storage.snapshot_authored()
	stage.call("_on_planning_pressed")
	var catalog := ObservedCatalog.new()
	catalog.bind_asset = planner.get("catalog").bind_asset
	var bind: Callable = catalog.bind_asset
	catalog.bind_asset = func(node: Node3D) -> void:
		_memory()
		bind.call(node)
	catalog.sample = _memory
	planner.get("objects").catalog = catalog
	storage._ensure_maps_dir()
	var path: String = storage._map_path("profile_named_map")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(MAP))
	file.close()
	return {"stage": stage, "storage": storage, "catalog": catalog, "path": path}


func _report(sync: bool, elapsed: int, baseline: int, records: int) -> void:
	print("NAMED_MAP_METRICS ", JSON.stringify({
		"route": "sync" if sync else "staged", "records": records,
		"elapsed_ms": elapsed / 1000.0, "frame_samples": samples.size(),
		"frame_mean_ms": _mean(), "frame_p95_ms": samples[int(ceil(samples.size() * 0.95)) - 1],
		"frame_max_ms": samples[-1], "allocator_baseline_mib": baseline / 1048576.0,
		"allocator_sampled_peak_mib": peak_memory / 1048576.0,
		"rss_sampled_peak_mib": peak_rss / 1048576.0,
		"slow_frames": spikes,
		"video_mib": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0}))


func _sample_frame() -> void:
	if not observing:
		return
	var now := Time.get_ticks_usec()
	var elapsed := (now - last_usec) / 1000.0
	samples.append(elapsed)
	if elapsed > 100.0:
		var phase := "completion"
		for child in planner.get_children():
			if child is CanvasLayer:
				var labels := child.find_children("*", "Label", true, false)
				if not labels.is_empty():
					phase = labels[0].text
		spikes.append({"ms": elapsed, "phase_after": phase})
	last_usec = now
	_memory()


func _memory() -> void:
	if not observing:
		return
	peak_memory = maxi(peak_memory, OS.get_static_memory_usage())
	var file := FileAccess.open("/proc/self/status", FileAccess.READ)
	if file != null:
		while not file.eof_reached():
			var line := file.get_line()
			if line.begins_with("VmRSS:"):
				peak_rss = maxi(peak_rss, int(line.trim_prefix("VmRSS:").strip_edges().get_slice(" ", 0)) * 1024)
				break


func _mean() -> float:
	var total := 0.0
	for value in samples:
		total += value
	return total / samples.size()
