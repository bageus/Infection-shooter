extends Node
## Mission-local lifetime for prop sound requests and their immutable streams.
const SFX := preload("res://game/core/audio/public/sound_events.gd")

var _pending: Dictionary[String, bool] = {}
var _streams: Dictionary[String, AudioStream] = {}


func _init() -> void:
	name = "AudioWarmup"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func start(events: Array[StringName]) -> void:
	for event in events:
		if not SFX.EVENTS.has(event):
			continue
		SFX.preload_event(event)
		for variant in range(1, int(SFX.EVENTS[event][SFX.VARIANTS]) + 1):
			var path := SFX.ROOT + "%s/%s_%d.ogg" % [event, event, variant]
			if not _streams.has(path):
				_pending[path] = true
	_collect_ready()
	set_process(not _pending.is_empty())


func _process(_delta: float) -> void:
	_collect_ready()
	set_process(not _pending.is_empty())


func _collect_ready() -> void:
	for path: String in _pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			# Another mission may already have collected the shared request.
			if ResourceLoader.has_cached(path):
				_streams[path] = load(path) as AudioStream
			elif ResourceLoader.load_threaded_request(path) == OK:
				# Its owner may also have exited before we could retain the stream.
				continue
		else:
			var stream := ResourceLoader.load_threaded_get(path) as AudioStream
			if stream != null:
				_streams[path] = stream
		_pending.erase(path)


func _exit_tree() -> void:
	# Only teardown may wait: Godot has no threaded-request cancellation API.
	# Complete requests even if the mission exits before its first process frame.
	for path: String in _pending:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(path)
	_pending.clear()
	_streams.clear()
