extends SceneTree
## O04: deterministic confirmed-hit workload; excludes AI, projectiles and real GPU time.
const FIXTURE := preload("res://game/features/infected/tests/blood_profile_fixture.gd")
var fixture := FIXTURE.new()
var options := {"weapon": "SHOTGUN", "mode": "full", "actors": "90", "frames": "600", "rate": "1.1", "pellets": "8", "capture": ""}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var fields := argument.trim_prefix("--").split("=", true, 1)
		assert(fields.size() == 2 and options.has(fields[0]), "Unknown profile argument: " + argument)
		options[fields[0]] = fields[1]
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(640, 360)
	fixture.weapon = options.weapon
	fixture.mode = options.mode
	var count := int(options.actors)
	var frames := int(options.frames)
	assert(count > 0 and frames > 0 and float(options.rate) > 0 and int(options.pellets) > 0)
	assert(options.mode in ["full", "stages", "scan"])
	var setup_started := Time.get_ticks_usec()
	fixture.setup(self, count)
	var setup_usec := Time.get_ticks_usec() - setup_started
	var cold: Array[int] = []
	# Cold first wound per body includes lazy masks/pages. Excluded from warm series.
	if options.mode != "scan":
		for index in count:
			cold.append(fixture.apply(fixture.event(index, 0)))
	var cold_counters := fixture.counters()
	fixture.reset_counters()
	for frame in 3:
		await process_frame
	var idle := await _idle(mini(frames, 60))
	var series := await _series(frames)
	var series_counters := fixture.counters()
	fixture.reset_counters()
	var repeated := _control(false)
	var repeated_counters := fixture.counters()
	fixture.reset_counters()
	var outside := _control(true)
	var outside_counters := fixture.counters()
	if DisplayServer.get_name() != "headless" and not str(options.capture).is_empty():
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(str(options.capture).path_join("crowd.png")) == OK)
	var result := {"protocol": options, "godot": Engine.get_version_info().string,
		"display_server": DisplayServer.get_name(), "configured_renderer": RenderingServer.get_current_rendering_method(),
		"setup_usec": setup_usec, "idle_process_frame_interval": idle, "topology": fixture.topology(), "cold_per_hit": _stats(cold),
		"cold_counters": cold_counters, "series": series, "series_counters": series_counters,
		"repeated_per_hit": _stats(repeated), "repeated_counters": repeated_counters,
		"outside_per_hit": _stats(outside), "outside_counters": outside_counters,
		"masks": fixture.masks(options.capture), "allocator_bytes": OS.get_static_memory_usage(),
		"video_memory_monitor_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"render_draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"render_primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))}
	print("BODY_BLOOD_METRICS ", JSON.stringify(result))
	fixture.stage.free()
	fixture.bodies.clear()
	for frame in 3:
		await process_frame
	quit()


func _idle(frames: int) -> Dictionary:
	var intervals: Array[int] = []
	var last_frame := Time.get_ticks_usec()
	for frame in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append(now - last_frame)
		last_frame = now
	return _stats(intervals)


func _series(frames: int) -> Dictionary:
	var rate := float(options.rate)
	var pellets := int(options.pellets)
	var batch_samples: Array[int] = []
	var hit_samples: Array[int] = []
	var intervals: Array[int] = []
	var ordinal := 0
	var last_frame := Time.get_ticks_usec()
	for frame in frames:
		var scheduled := int(floor(float(frame) * rate / 60.0 + .000001))
		var previous := int(floor(float(frame - 1) * rate / 60.0 + .000001)) if frame > 0 else -1
		if scheduled > previous:
			var hits: Array[Dictionary] = []
			for pellet in pellets:
				var actor := (ordinal * 17 + pellet % 3) % fixture.bodies.size()
				hits.append(fixture.event(actor, 1 + ordinal * pellets + pellet))
			var started := Time.get_ticks_usec()
			for hit in hits:
				hit_samples.append(fixture.apply(hit))
			batch_samples.append(Time.get_ticks_usec() - started)
			ordinal += 1
		await process_frame
		var now := Time.get_ticks_usec()
		intervals.append(now - last_frame)
		last_frame = now
	return {"bursts": ordinal, "hits": hit_samples.size(), "per_hit": _stats(hit_samples),
		"active_batch": _stats(batch_samples), "observed_process_frame_interval": _stats(intervals),
		"active_batches_over_16_667_ms": batch_samples.filter(func(value: int) -> bool: return value > 16667).size()}


func _control(off_body: bool) -> Array[int]:
	var samples: Array[int] = []
	var hit := fixture.event(0, 0)
	if off_body:
		hit.center = Vector3(0, 1000000, 0)
	for index in 12:
		samples.append(fixture.apply(hit))
	return samples


func _stats(source: Array[int]) -> Dictionary:
	if source.is_empty():
		return {"samples": 0}
	var samples := source.duplicate()
	samples.sort()
	var total := 0
	for sample in samples:
		total += sample
	return {"samples": samples.size(), "mean_usec": float(total) / samples.size(),
		"p95_usec": samples[int(ceil(samples.size() * .95)) - 1], "max_usec": samples[-1], "total_usec": total}
