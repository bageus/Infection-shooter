extends RefCounted
## F7 debug probe: switches one rendering feature off at a time (shadows, lamps, particles, resolution, all 3D)
## for a few seconds each and writes the average frame, GPU and render-CPU time of every step to the frame log, so
## it shows what the frame really costs on this GPU. Stand still in a quiet spot; the whole run takes about 40 s.
const LOG := preload("res://game/bootstrap/app/frame_spike_log.gd")
const STEPS := ["baseline", "shadows off", "14 lamps", "7 lamps", "no lamps", "particles off", "half resolution", "3D off", "baseline again"]
const SETTLE := 1.5
const MEASURE := 4.0
const SAVED := &"render_probe_saved"

var path := LOG.PATH
var running := false
var _step := 0
var _age := 0.0
var _frames := 0
var _frame_sum := 0.0
var _cpu_sum := 0.0
var _gpu_sum := 0.0
var _shadows := true
var _cap := 0
var _scale := 1.0
var _results: Array[String] = []


func start(tree: SceneTree) -> void:
	if running or tree == null:
		return
	running = true
	_results = []
	_scale = tree.root.scaling_3d_scale
	var lighting := _lighting(tree)
	if lighting != null:
		_shadows = bool(lighting.get("shadows_allowed"))
		_cap = int(lighting.get("light_cap"))
	_enter(tree, 0)


func tick(delta: float, tree: SceneTree) -> void:
	if not running:
		return
	_age += delta
	if _age < SETTLE:
		return
	var viewport := tree.root.get_viewport_rid()
	_frames += 1
	_frame_sum += delta * 1000.0
	_cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
	_gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	if _age >= SETTLE + MEASURE:
		_finish_step(tree)


func status() -> String:
	return "render probe: %s (%d/%d)" % [STEPS[_step], _step + 1, STEPS.size()] if running else ""


func _enter(tree: SceneTree, step: int) -> void:
	_restore(tree)
	_step = step
	_age = 0.0
	_frames = 0
	_frame_sum = 0.0
	_cpu_sum = 0.0
	_gpu_sum = 0.0
	var lighting := _lighting(tree)
	match step:
		1:
			if lighting != null:
				lighting.call("set_shadows_allowed", false)
		2, 3, 4:
			if lighting != null:
				lighting.set("light_cap", [14, 7, 0][step - 2])
				lighting.call("refresh_light_budget")
		5:
			for node: Node3D in _nodes(tree, "GPUParticles3D") + _nodes(tree, "CPUParticles3D"):
				if node.visible:
					node.set_meta(SAVED, true)
					node.visible = false
		6:
			tree.root.scaling_3d_scale = 0.5
		7:
			tree.root.disable_3d = true


func _finish_step(tree: SceneTree) -> void:
	var n := maxf(1.0, float(_frames))
	var frame := _frame_sum / n
	_results.append("%s=%.1fms(%.0ffps) rgpu=%.1f rcpu=%.1f" % [STEPS[_step], frame, 1000.0 / maxf(frame, 0.1), _gpu_sum / n, _cpu_sum / n])
	if _step + 1 < STEPS.size():
		_enter(tree, _step + 1)
		return
	_restore(tree)
	running = false
	var line := "render_probe " + " | ".join(_results)
	print(line)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)


# Puts back only what this probe changed.
func _restore(tree: SceneTree) -> void:
	tree.root.scaling_3d_scale = _scale
	tree.root.disable_3d = false
	var lighting := _lighting(tree)
	if lighting != null and int(lighting.get("light_cap")) != _cap:
		lighting.set("light_cap", _cap)
		lighting.call("refresh_light_budget")
	if lighting != null and bool(lighting.get("shadows_allowed")) != _shadows:
		lighting.call("set_shadows_allowed", _shadows)
	for node: Node3D in _nodes(tree, "GPUParticles3D") + _nodes(tree, "CPUParticles3D"):
		if node.has_meta(SAVED):
			node.remove_meta(SAVED)
			node.visible = true


func _lighting(tree: SceneTree) -> Node:
	return tree.current_scene.get_node_or_null("PlanningLighting") if tree.current_scene != null else null


func _nodes(tree: SceneTree, type: String) -> Array:
	return tree.root.find_children("*", type, true, false)
