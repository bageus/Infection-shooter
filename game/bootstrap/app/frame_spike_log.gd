extends RefCounted
## Watches frame times while the F3 overlay is open and writes every long frame to user://frame_spikes.log
## with what changed around it (loaded resources, node count, memory, draw calls, player position), so a
## stutter can be traced to loading, spawning or rendering instead of guessed.
const PATH := "user://frame_spikes.log"
const SPIKE_MSEC := 40.0
const WINDOW_SEC := 5.0
var spikes := 0
var worst_msec := 0.0
var _window_worst := 0.0
var _window_age := 0.0
var _resources := 0
var _nodes := 0
var _path := PATH


## Call once per frame with the frame time in seconds; returns true when this frame was logged.
func tick(delta: float, tree: SceneTree) -> bool:
	var msec := delta * 1000.0
	_window_age += delta
	if _window_age >= WINDOW_SEC:
		_window_age = 0.0
		_window_worst = 0.0
	_window_worst = maxf(_window_worst, msec)
	var resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var logged := false
	if msec >= SPIKE_MSEC:
		spikes += 1
		worst_msec = maxf(worst_msec, msec)
		_write(msec, resources, nodes, tree)
		logged = true
	_resources = resources
	_nodes = nodes
	return logged


func summary() -> String:
	return "Spikes: worst 5 s %.0f ms | frames over %.0f ms: %d (worst %.0f) | log %s" % [_window_worst, SPIKE_MSEC, spikes, worst_msec, PATH]


func _write(msec: float, resources: int, nodes: int, tree: SceneTree) -> void:
	var player := tree.get_first_node_in_group("player") as Node3D if tree != null else null
	var at := "%.1f,%.1f" % [player.global_position.x, player.global_position.z] if player != null else "?"
	var file := FileAccess.open(_path, FileAccess.READ_WRITE if FileAccess.file_exists(_path) else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("t=%.1fs frame=%.0fms process=%.1f physics=%.1f draw=%d objects=%d resources=%+d nodes=%+d (%d) static=%dMiB video=%dMiB player=%s" % [
		Time.get_ticks_msec() / 1000.0, msec, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		resources - _resources, nodes - _nodes, nodes, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, at])
