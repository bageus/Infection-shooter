extends SceneTree
## First-time mutation training: step data, phase triggers, one-time memory and the overlay gate.
const SCRIPT := preload("res://game/bootstrap/app/mutation_tutorial_script.gd")
const TUTORIAL := preload("res://game/bootstrap/app/mutation_tutorial.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const SAVE_PATH := "user://mutation_tutorial_test.cfg"
var failures := 0


class FakeRuntime extends Node:
	signal skill_available
	var mutation := 0.0
	var control_lost := false
	var learned := false

	func get_mutation() -> float:
		return mutation

	func is_control_lost() -> bool:
		return control_lost

	func skill_learned(_skill_id: String) -> bool:
		return learned


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_step_data()
	await _check_scale_flow()
	print("Mutation tutorial tests: %d failure(s)." % failures)
	quit(failures)


func _check_step_data() -> void:
	for phase in [SCRIPT.PHASE_SCALE, SCRIPT.PHASE_BRANCHES, SCRIPT.PHASE_LOSS]:
		var steps := SCRIPT.steps(phase)
		_expect(not steps.is_empty(), "Phase %s has steps" % phase)
		for step: Dictionary in steps:
			var key := str(step["text"])
			_expect(key == "" or not _is_untranslated(key), "Text key %s is translated" % key)
	_expect(SCRIPT.steps(&"unknown").is_empty(), "An unknown phase has no steps")
	_expect(SCRIPT.steps(SCRIPT.PHASE_BRANCHES).size() == 6, "The branch phase has six steps")


func _is_untranslated(key: String) -> bool:
	var text := TEXT.t(key)
	return text == key or text == ""


func _check_scale_flow() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	var runtime := FakeRuntime.new()
	root.add_child(runtime)
	var tutorial := TUTORIAL.new()
	tutorial.save_path = SAVE_PATH
	root.add_child(tutorial)
	tutorial.call("setup", runtime, {}, null)
	await create_timer(0.1).timeout
	_expect(tutorial.get("_phase") == &"", "No training starts below the scale trigger")
	runtime.mutation = 5.0
	await create_timer(0.1).timeout
	_expect(tutorial.get("_phase") == SCRIPT.PHASE_SCALE, "Reaching 5 starts the scale training")
	var overlay := tutorial.get("_overlay") as Control
	_expect(overlay.visible, "The overlay shows the first scale step")
	for _step in SCRIPT.steps(SCRIPT.PHASE_SCALE).size():
		tutorial.call("_advance")
	_expect(tutorial.get("_phase") == &"" and not overlay.visible, "Finishing the scale steps hides the overlay")
	await create_timer(0.1).timeout
	_expect(tutorial.get("_phase") == &"", "A finished phase does not start again")
	tutorial.free()
	var again := TUTORIAL.new()
	again.save_path = SAVE_PATH
	root.add_child(again)
	again.call("setup", runtime, {}, null)
	await create_timer(0.1).timeout
	_expect(again.get("_phase") == &"", "Finished phases are remembered across runs")
	again.free()
	runtime.free()
	DirAccess.remove_absolute(SAVE_PATH)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
