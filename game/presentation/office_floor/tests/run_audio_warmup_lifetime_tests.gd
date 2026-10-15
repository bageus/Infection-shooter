extends SceneTree
const AUDIO := preload("res://game/presentation/office_floor/audio_warmup.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const EVENTS: Array[StringName] = [&"hit_metal", &"hit_wood", &"missing_event"]
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _shared_owners()
	await _early_exit_and_restart()
	await _departed_owner()
	print("Audio warmup lifetime tests: %d failure(s)." % failures)
	quit(1 if failures else 0)


func _shared_owners() -> void:
	var mission := Node.new()
	root.add_child(mission)
	var audio := AUDIO.new()
	mission.add_child(audio)
	audio.start(EVENTS)
	audio.start(EVENTS)
	# A second overlapping mission must not duplicate or strand shared requests.
	var other := AUDIO.new()
	mission.add_child(other)
	other.start(EVENTS)
	paused = true
	var deadline := Time.get_ticks_msec() + 10000
	while (not audio._pending.is_empty() or not other._pending.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	paused = false
	_check(audio._pending.is_empty() and other._pending.is_empty(), "Both owners finish while paused")
	_check(audio._streams.size() == 9 and other._streams.size() == 9, "All variants remain owned after warmup")
	_check(not audio.is_processing() and not other.is_processing(), "Completed owners stop polling")
	var retained: WeakRef = weakref(audio._streams.values()[0])
	for path: String in audio._streams:
		_check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "Request consumed: " + path)
		_check(audio._streams[path] == other._streams[path], "Owners share immutable cached stream")
	var before := audio._streams.duplicate()
	audio.start(EVENTS)
	_check(audio._streams == before and audio._pending.is_empty(), "Repeated start keeps existing streams")
	before.clear()
	mission.free()
	audio = null
	other = null
	_check(retained.get_ref() == null, "Mission teardown releases retained streams")


func _early_exit_and_restart() -> void:
	# Exit on the same frame as submission, before normal polling can run.
	var early := AUDIO.new()
	root.add_child(early)
	var early_events: Array[StringName] = [&"glass_break"]
	early.start(early_events)
	early.free()
	for variant in range(1, 5):
		var path := SFX.ROOT + "glass_break/glass_break_%d.ogg" % variant
		_check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "Early exit completes request")
	var restarted := AUDIO.new()
	root.add_child(restarted)
	restarted.start(EVENTS)
	var deadline := Time.get_ticks_msec() + 10000
	while not restarted._pending.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(restarted._streams.size() == 9, "Next mission can warm the same events again")
	restarted.free()


func _departed_owner() -> void:
	# Reproduce a shared result being collected and released before our poll.
	var path := SFX.ROOT + "break_lamp/break_lamp_1.ogg"
	ResourceLoader.load_threaded_request(path)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await process_frame
	var previous := ResourceLoader.load_threaded_get(path) as AudioStream
	previous = null
	var audio := AUDIO.new()
	root.add_child(audio)
	audio._pending[path] = true
	audio.set_process(true)
	var deadline := Time.get_ticks_msec() + 10000
	while not audio._pending.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(audio._streams.size() == 1, "Departed shared owner cannot lose our warmup")
	_check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "Replacement request is consumed")
	audio.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
