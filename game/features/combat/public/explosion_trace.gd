extends Node
## Diagnostic only: times the phases of a grenade blast and an extinguisher shot/rupture and
## logs every slow frame that follows, to tell CPU work (a slow phase) from GPU shader or texture
## stalls (all phases fast, a slow frame after). Off unless the game runs with the user argument
## `explosion-trace`, the environment variable EXPLOSION_TRACE, or a file user://explosion_trace.flag.
## Writes to user://explosion_trace.log and prints the same lines.
const LOG_PATH := "user://explosion_trace.log"
const FLAG_PATH := "user://explosion_trace.flag"
const WINDOW_SEC := 6.0
const SLOW_FRAME_MS := 30.0
const IDLE_SPIKE_MS := 100.0

static var _enabled := -1
static var _instance: Node

var _event := ""
var _event_start := 0
var _last_frame := 0
var _file: FileAccess


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 1 if OS.get_cmdline_user_args().has("explosion-trace") or OS.has_environment("EXPLOSION_TRACE") or FileAccess.file_exists(FLAG_PATH) else 0
	return _enabled == 1


## Creates the frame monitor at game start, so slow frames before the first traced event are logged too.
static func start() -> void:
	_trace()


## Starts a traced event; later marks and slow frames are reported relative to it.
static func begin(event: String) -> void:
	var trace := _trace()
	if trace != null:
		trace._begin(event)


static func mark(label: String) -> void:
	var trace := _trace()
	if trace != null:
		trace._mark(label)


static func _trace() -> Node:
	if not enabled():
		return null
	if not is_instance_valid(_instance):
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return null
		_instance = (load("res://game/features/combat/public/explosion_trace.gd") as GDScript).new()
		_instance.name = "ExplosionTrace"
		tree.root.add_child(_instance)
	return _instance


func _begin(event: String) -> void:
	_event = event
	_event_start = Time.get_ticks_usec()
	_write("=== %s (nodes=%d, objects=%d, draw_calls=%d, texture_mem=%.0f MB)" % [event, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])


func _mark(label: String) -> void:
	_write("  +%.1f ms  %s" % [(Time.get_ticks_usec() - _event_start) / 1000.0, label])


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_frame) / 1000.0 if _last_frame > 0 else 0.0
	_last_frame = now
	var since := (now - _event_start) / 1000000.0
	if _event != "" and since <= WINDOW_SEC:
		if frame_ms >= SLOW_FRAME_MS:
			_write("  slow frame %.0f ms at +%.2f s after %s" % [frame_ms, since, _event])
	elif frame_ms >= IDLE_SPIKE_MS:
		_write("  frame spike %.0f ms outside any traced event" % frame_ms)


func _write(line: String) -> void:
	line = "[%.2f] %s" % [Time.get_ticks_msec() / 1000.0, line]
	print("EXPLOSION_TRACE ", line)
	if _file == null:
		_file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
		if _file == null:
			return
		_file.seek_end()
		_file.store_line("--- session %s, log at %s" % [Time.get_datetime_string_from_system(), ProjectSettings.globalize_path(LOG_PATH)])
	_file.store_line(line)
	_file.flush()
