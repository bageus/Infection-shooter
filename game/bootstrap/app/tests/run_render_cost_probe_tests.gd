extends SceneTree
## The F7 render-cost probe steps through every feature, writes one summary line, and puts back exactly what it changed.
const PROBE := preload("res://game/bootstrap/app/render_cost_probe.gd")
const PATH := "user://render_probe_test.log"
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	var shadowed := DirectionalLight3D.new()
	shadowed.shadow_enabled = true
	var hidden := OmniLight3D.new()
	hidden.visible = false
	root.add_child(shadowed)
	root.add_child(hidden)
	var msaa := root.msaa_3d
	var probe := PROBE.new()
	probe.path = PATH
	probe.start(self)
	_check(probe.running, "the probe starts")
	var guard := 0
	while probe.running and guard < 2000:
		probe.tick(0.05, self)
		guard += 1
	_check(not probe.running, "the probe finishes")
	_check(shadowed.shadow_enabled and shadowed.visible, "a shadowed light is restored")
	_check(not hidden.visible, "a light that was hidden stays hidden")
	_check(root.msaa_3d == msaa and is_equal_approx(root.scaling_3d_scale, 1.0) and not root.disable_3d, "viewport settings are restored")
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
