extends RefCounted
## Watches frame times while the F3 overlay is open and writes every long frame to user://frame_spikes.log
## with what changed around it (loaded resources, node count, memory, draw calls, player position), so a
## stutter can be traced to loading, spawning or rendering instead of guessed.
const PATH := "user://frame_spikes.log"
const SPIKE_MSEC := 40.0
const WINDOW_SEC := 5.0
var spikes := 0
var probe_mode := 0 # F5 enemy render probe step, logged so a log can be split by mode.
var worst_msec := 0.0
var _window_worst := 0.0
var _window_age := 0.0
var _resources := 0
var _nodes := 0
var _path := PATH
var _rigid_bodies: Array = []
var _rigid_at := 0


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
	var hidden := _culled(tree)
	var plan := _plan_state(tree)
	var rigid := _rigid(tree)
	file.store_line("t=%.1fs frame=%.0fms process=%.1f physics=%.1f draw=%d objects=%d resources=%+d nodes=%+d (%d) static=%dMiB video=%dMiB enemies=%d culled=%d/%d merged=%d trim=%d/%d rigid=%d awake=%d probe=%d player=%s" % [
		Time.get_ticks_msec() / 1000.0, msec, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		resources - _resources, nodes - _nodes, nodes, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		(tree.get_nodes_in_group("infected_alive").size() if tree != null else 0), hidden[0], hidden[1], plan[0], plan[1], plan[2], rigid[0], rigid[1], probe_mode, at])


# Room-culled furniture: [hidden now, tagged in total].
func _culled(tree: SceneTree) -> Array:
	var props := tree.get_nodes_in_group(&"room_prop") if tree != null else []
	return [props.filter(func(prop): return not prop.visible).size(), props.size()]


# Scene state every way into play must reach alike: [merged source meshes, trim-hidden decor, trimmable decor].
func _plan_state(tree: SceneTree) -> Array:
	if tree == null:
		return [0, 0, 0]
	var merged := 0
	for holder in tree.get_nodes_in_group(&"static_merged"):
		merged += (holder.get_meta(&"static_merge_sources", []) as Array).size()
	var trimmed := tree.get_nodes_in_group(&"trim_decor")
	return [merged, trimmed.filter(func(node): return not node.visible).size(), trimmed.size()]


# Physics monitors read 0 with Jolt, so count the rigid bodies ourselves: [all, awake]. The tree is walked at most every 5 s.
func _rigid(tree: SceneTree) -> Array:
	if tree == null or tree.current_scene == null:
		return [0, 0]
	if _rigid_bodies.is_empty() or Time.get_ticks_msec() - _rigid_at > 5000:
		_rigid_at = Time.get_ticks_msec()
		_rigid_bodies = tree.current_scene.find_children("*", "RigidBody3D", true, false)
	var awake := 0
	for body in _rigid_bodies:
		if is_instance_valid(body) and not (body as RigidBody3D).sleeping:
			awake += 1
	return [_rigid_bodies.size(), awake]
