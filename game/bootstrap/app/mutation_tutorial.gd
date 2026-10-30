extends Node
## Runs the first-time mutation training: each phase starts once, its steps show in order,
## and finished phases are remembered in a small config file so they never repeat.

const SCRIPT := preload("res://game/bootstrap/app/mutation_tutorial_script.gd")
const OVERLAY := preload("res://game/bootstrap/app/mutation_tutorial_overlay.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const DEFAULT_SAVE_PATH := "user://mutation_tutorial.cfg"
const SECTION := "tutorial"
const OVERLAY_LAYER := 130
const POWER_STRIKE := "power_strike"
const POWER_STRIKE_BRANCH := 2
const STRIKE_TARGET_HALF := 22.0
const BRANCH_LABEL_X := 24.0
const BRANCH_LABEL_WIDTH := 160.0
const BRANCH_LABEL_HEIGHT := 20.0
# Canvas positions of the section labels drawn by mutation_tree_ui.gd.
const ACTIVE_LABEL_Y := 185.0
const PASSIVE_LABEL_Y := 490.0

var save_path := DEFAULT_SAVE_PATH
var _runtime: Node
var _targets: Dictionary = {}
var _tree_ui: Node
var _overlay: Control
var _done: Dictionary = {}
var _phase: StringName = &""
var _steps: Array = []
var _index := 0
var _skill_seen := false


## `targets` maps the HUD target ids (mutation_bar, antidote, gas_mask) to their controls.
func setup(runtime: Node, targets: Dictionary, tree_ui: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_runtime = runtime
	_targets = targets
	_tree_ui = tree_ui
	_load_progress()
	var layer := CanvasLayer.new()
	layer.layer = OVERLAY_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_overlay = OVERLAY.new()
	layer.add_child(_overlay)
	_overlay.acknowledged.connect(_advance)
	runtime.connect("skill_available", _on_skill_available)


func _process(_delta: float) -> void:
	if _runtime == null:
		return
	if _phase == &"":
		_start_next_phase()
		return
	if _phase == SCRIPT.PHASE_BRANCHES:
		# The branch steps live on the mutation tree; they wait while the tree is closed.
		_overlay.visible = _tree_open()
	var step: Dictionary = _steps[_index]
	if step["advance"] == SCRIPT.ADVANCE_POWER_STRIKE_LEARNED and bool(_runtime.call("skill_learned", POWER_STRIKE)):
		_advance()


func _start_next_phase() -> void:
	var playing := not get_tree().paused
	if playing and not _is_done(SCRIPT.PHASE_SCALE) and float(_runtime.call("get_mutation")) >= SCRIPT.SCALE_TRIGGER:
		_start(SCRIPT.PHASE_SCALE)
	elif not _is_done(SCRIPT.PHASE_BRANCHES) and _skill_seen and _tree_open():
		_start(SCRIPT.PHASE_BRANCHES)
	elif playing and not _is_done(SCRIPT.PHASE_LOSS) and bool(_runtime.call("is_control_lost")):
		_start(SCRIPT.PHASE_LOSS)


func _start(phase: StringName) -> void:
	_phase = phase
	_steps = SCRIPT.steps(phase)
	_index = 0
	_show_step()


func _show_step() -> void:
	if _index >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_index]
	var rects: Array[Rect2] = []
	for target_id in step["targets"]:
		var rect := _rect(str(target_id))
		if rect.has_area():
			rects.append(rect)
	var text := TEXT.t(str(step["text"])) if str(step["text"]) != "" else ""
	_overlay.show_step(text, rects, float(step["dim"]), bool(step["blocks"]), bool(step["arrow"]), step["advance"] == SCRIPT.ADVANCE_PRESS)


func _advance() -> void:
	if _phase == &"":
		return
	_index += 1
	_show_step()


func _finish() -> void:
	_done[_phase] = true
	_save_progress()
	_phase = &""
	_steps.clear()
	_overlay.clear()


func _on_skill_available() -> void:
	_skill_seen = true


func _is_done(phase: StringName) -> bool:
	return bool(_done.get(phase, false))


func _tree_open() -> bool:
	return _tree_ui != null and bool(_tree_ui.call("is_tree_open"))


## Screen rectangle of a target; empty when the target is not on screen.
func _rect(target_id: String) -> Rect2:
	if target_id.begins_with("tree_"):
		return _tree_rect(target_id)
	var control := _targets.get(target_id) as Control
	if control == null or not control.is_visible_in_tree():
		return Rect2()
	return control.get_global_rect()


func _tree_rect(target_id: String) -> Rect2:
	var content := _tree_ui.get("content") as Control
	if content == null or content.get_child_count() == 0:
		return Rect2()
	var canvas := content.get_child(0) as Control
	var to_screen := canvas.get_global_transform()
	match target_id:
		"tree_active":
			return to_screen * Rect2(BRANCH_LABEL_X, ACTIVE_LABEL_Y, BRANCH_LABEL_WIDTH, BRANCH_LABEL_HEIGHT)
		"tree_passive":
			return to_screen * Rect2(BRANCH_LABEL_X, PASSIVE_LABEL_Y, BRANCH_LABEL_WIDTH, BRANCH_LABEL_HEIGHT)
		"tree_power_strike":
			var centre: Vector2 = canvas.call("skill_position", POWER_STRIKE_BRANCH, 0)
			return to_screen * Rect2(centre - Vector2.ONE * STRIKE_TARGET_HALF, Vector2.ONE * STRIKE_TARGET_HALF * 2.0)
	return Rect2()


func _load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	for phase in [SCRIPT.PHASE_SCALE, SCRIPT.PHASE_BRANCHES, SCRIPT.PHASE_LOSS]:
		_done[phase] = bool(config.get_value(SECTION, String(phase), false))


func _save_progress() -> void:
	var config := ConfigFile.new()
	config.load(save_path)
	for phase in _done:
		config.set_value(SECTION, String(phase), bool(_done[phase]))
	config.save(save_path)
