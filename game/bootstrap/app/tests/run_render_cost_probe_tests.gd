extends SceneTree
## The F7 render-cost probe steps through every feature, writes one summary line, and puts back exactly what it changed.
const PROBE := preload("res://game/bootstrap/app/render_cost_probe.gd")
const PATH := "user://render_probe_test.log"
var failures := 0


class Lighting extends Node:
	var shadows_allowed := true
	var light_cap := 28
	var caps: Array[int] = []

	func set_shadows_allowed(allowed: bool) -> void:
		shadows_allowed = allowed

	func refresh_light_budget() -> void:
		caps.append(light_cap)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	var scene := Node3D.new()
	var lighting := Lighting.new()
	lighting.name = "PlanningLighting"
	scene.add_child(lighting)
	root.add_child(scene)
	current_scene = scene
	var particles := GPUParticles3D.new()
	scene.add_child(particles)
	var probe := PROBE.new()
	probe.path = PATH
	probe.start(self)
	_check(probe.running, "the probe starts")
	var guard := 0
	while probe.running and guard < 2000:
		probe.tick(0.05, self)
		guard += 1
	_check(not probe.running, "the probe finishes")
	_check(lighting.shadows_allowed and lighting.light_cap == 28, "shadows and the lamp budget are restored")
	_check(lighting.caps.has(14) and lighting.caps.has(7) and lighting.caps.has(0), "the lamp budget was lowered step by step")
	_check(particles.visible, "particles are shown again")
	_check(is_equal_approx(root.scaling_3d_scale, 1.0) and not root.disable_3d, "viewport settings are restored")
	var text := FileAccess.get_file_as_string(PATH)
	for name: String in PROBE.STEPS:
		_check(text.contains(name + "="), "the summary names the step " + name)
	DirAccess.remove_absolute(PATH)
	print("Render cost probe tests: %d failure(s)" % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
