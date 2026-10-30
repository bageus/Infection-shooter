extends Node
## Decides when the first-time lessons start and what their steps are, then feeds them to the overlay.
## Lessons: mutation scale and antidote, active skill, passive skill and locking, control loss and gas mask.
## One lesson plays at a time; later ones wait in a queue. Seen lessons are remembered on disk.

const OVERLAY := preload("res://game/bootstrap/app/tutorial/tutorial_overlay.gd")
const PROGRESS := preload("res://game/bootstrap/app/tutorial/tutorial_progress.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const SCALE_TRIGGER := 5.0

var overlay: Node
var progress: RefCounted
var current := ""
var _queue: Array[String] = []
var _steps: Array = []
var _runtime: Node
var _hud: Node
var _tree_ui: Node
var _player: Node
var _started_mutation := 0.0


func configure(player: Node, hud: Node, tree_ui: Node, progress_state: RefCounted = null) -> void:
	_player = player
	_hud = hud
	_tree_ui = tree_ui
	_runtime = player.get("infection_runtime")
	progress = progress_state if progress_state != null else PROGRESS.new()
	overlay = OVERLAY.new()
	overlay.name = "TutorialOverlay"
	add_child(overlay)
	overlay.step_finished.connect(_next_step)
	_runtime.mutation_changed.connect(_on_mutation_changed)
	_runtime.skill_available.connect(_on_skill_available)
	_runtime.control_loss_changed.connect(_on_control_loss_changed)


func request(lesson: String) -> void:
	if progress.is_done(lesson) or lesson == current or lesson in _queue:
		return
	# Losing control cannot wait: the lesson in progress restarts after it.
	if lesson == "control_loss" and not current.is_empty():
		overlay.call("finish", false)
		_queue.push_front(current)
		current = ""
		_queue.push_front(lesson)
		_start_next()
		return
	_queue.append(lesson)
	if current.is_empty():
		_start_next()


func _on_mutation_changed(amount: float, _limit: float) -> void:
	if amount >= SCALE_TRIGGER and not bool(_runtime.call("is_control_lost")):
		request("mutation_scale")


func _on_skill_available() -> void:
	if bool(_runtime.call("is_control_lost")) or bool(_runtime.call("is_defeated")):
		return
	if bool(_runtime.call("can_upgrade_skill", "power_strike")):
		request("active_skill")
	elif (current == "active_skill" or progress.is_done("active_skill")) and bool(_runtime.call("can_upgrade_skill", "muscle_memory")):
		request("passive_skill")


func _on_control_loss_changed(active: bool) -> void:
	if active:
		request("control_loss")


func _start_next() -> void:
	if _queue.is_empty():
		current = ""
		return
	current = _queue.pop_front()
	_steps = _build_steps(current)
	_started_mutation = float(_runtime.call("get_mutation"))
	if current == "active_skill" or current == "passive_skill":
		_tree_ui.call("open_tree")
	_next_step()


func _next_step() -> void:
	if _steps.is_empty():
		progress.mark_done(current)
		_start_next()
		return
	var step: Dictionary = _steps.pop_front()
	overlay.call("play", step)


func _build_steps(lesson: String) -> Array:
	var mutation := _hud_rect.bind("mutation")
	var antidote := _hud_rect.bind("antidote")
	var antidote_key := _binding("antidote")
	match lesson:
		"mutation_scale":
			return [
				_click(TEXT.t("tutMeterGrow"), [mutation]),
				_picture(TEXT.t("tutMeterLimit")),
				_click(TEXT.t("tutAntidote") % antidote_key, [antidote]),
				_click(TEXT.t("tutAntidoteWise"), [antidote]),
			]
		"active_skill":
			return [
				_click(TEXT.t("tutBranches"), [_tree_rect.bind("active"), _tree_rect.bind("passive")], _tree_open),
				_click(TEXT.t("tutActive"), [_tree_rect.bind("active")], _tree_open),
				_click(TEXT.t("tutPassive"), [_tree_rect.bind("passive")], _tree_open),
				_wait(TEXT.t("tutPickPower"), [_tree_rect.bind("skill:power_strike")], _power_strike_chosen, _tree_open, true),
				_hint(TEXT.t("tutKillActive") % _binding("skill_1"), _skill_ready.bind("muscle_memory")),
			]
		"passive_skill":
			return [
				_wait(TEXT.t("tutPickReload"), [_tree_rect.bind("skill:muscle_memory")], _skill_learned.bind("muscle_memory"), _tree_open, true),
				_click(TEXT.t("tutLock"), [_tree_rect.bind("skill:lock:muscle_memory")], _tree_open),
			]
		"control_loss":
			return [
				_click(TEXT.t("tutLostControl"), [mutation]),
				_wait(TEXT.t("tutUseAntidote") % antidote_key, [antidote], _antidote_used, Callable(), true),
				_click(TEXT.t("tutAntidoteEffect"), [mutation]),
				_click(TEXT.t("tutGasMask") % "TAB", [_hud_rect.bind("gas_mask")]),
			]
	return []


func _click(text: String, targets: Array, requires: Callable = Callable()) -> Dictionary:
	return {"text": text, "targets": targets, "mode": "click", "requires": requires}


func _picture(text: String) -> Dictionary:
	return {"text": text, "targets": [], "mode": "click", "picture": true,
		"mutation": _runtime.call("get_mutation"), "threshold": _runtime.call("get_critical_threshold")}


func _hint(text: String, done: Callable) -> Dictionary:
	return {"text": text, "targets": [], "mode": "wait", "done": done, "hint": true, "dim": false}


func _wait(text: String, targets: Array, done: Callable, requires: Callable, arrow: bool, dim: bool = true) -> Dictionary:
	return {"text": text, "targets": targets, "mode": "wait", "done": done, "requires": requires, "arrow": arrow, "dim": dim}


func _hud_rect(kind: String) -> Rect2:
	return _hud.call("tutorial_rect", kind)


func _tree_rect(kind: String) -> Rect2:
	return _tree_ui.call("tutorial_rect", kind)


func _tree_open() -> bool:
	return bool(_tree_ui.call("is_tree_open"))


func _skill_learned(skill_id: String) -> bool:
	return bool(_runtime.call("skill_learned", skill_id))


# The first point is spent: on Power Strike, or on whatever else the player preferred.
func _power_strike_chosen() -> bool:
	return _skill_learned("power_strike") or int(_runtime.call("mutation_points")) <= 0


func _skill_ready(skill_id: String) -> bool:
	return bool(_runtime.call("can_upgrade_skill", skill_id)) or _skill_learned(skill_id)


# Control is back and the dose was spent: mutation dropped, or nothing was left to spend.
func _antidote_used() -> bool:
	if float(_runtime.call("get_mutation")) < _started_mutation - 0.5:
		return true
	return not bool(_runtime.call("is_control_lost")) and _player.antidotes <= 0 and not _player.infinite_antidotes


func _binding(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "?"
	var event: InputEvent = events[0]
	if event is InputEventMouseButton:
		return ["LMB", "RMB", "MMB"][clampi(event.button_index - 1, 0, 2)]
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)
	return event.as_text()
