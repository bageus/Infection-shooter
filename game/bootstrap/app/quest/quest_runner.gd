extends Node
## Plays the map's quests one after another: wait for the trigger, wait the delay, show the task,
## wait for its completion, then move on to the next. Nothing starts while the planner is open.

const LOGIC := preload("res://game/bootstrap/app/quest/quest_logic.gd")
const BOOK := preload("res://game/bootstrap/app/quest/quest_book.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const MESSAGE_SECONDS := 6.0
const TELEPORT := 3.0
const MODEL := preload("res://game/bootstrap/app/quest/quest_model.gd")

enum Phase { TRIGGER, DELAY, ACTIVE, DONE }

var book: Node
var player: Node3D
var hud: Node
var director: Node # may be null (headless runs have no lessons)
var host: Node
var index := 0
var phase := Phase.TRIGGER
var _idle := 0.0
var _delay := 0.0
var _message_left := 0.0
var _walked := 0.0
var _walked_at_start := 0.0
var _last_position := Vector3.INF
var _targets: Array = []
var _mutation_last := 0.0
var _mutation_rise := 0.0 # everything the meter climbed since the quest began; falls do not count back
var _trigger_node: Node3D
var _trigger_existed := false
var _was_planning := false
var _objective_text := "" # the quest text as stored; shown through MODEL.display_text


func configure(quest_book: Node, hero: Node3D, interface: Node, lessons: Node, owner_node: Node) -> void:
	book = quest_book
	player = hero
	hud = interface
	director = lessons
	host = owner_node
	# The mutation menu pauses the game, and "menu open" must still be noticed, so the runner keeps running then.
	process_mode = Node.PROCESS_MODE_ALWAYS
	book.changed.connect(reset)


func reset() -> void:
	index = 0
	_point_floor(Callable())
	_begin_quest()
	_set_objective("")
	BOOK.show_markers(get_tree(), [])


func current() -> Dictionary:
	return book.quests[index] if index < book.quests.size() else {}


func is_finished() -> bool:
	return index >= book.quests.size()


func _planning() -> bool:
	var mode: Variant = host.get("planning_mode") if host != null else null
	return mode != null and bool(mode.get("active"))


func _process(delta: float) -> void:
	if player == null or book == null or (get_tree().paused and not _menu_open()):
		return
	var planning := _planning()
	if planning:
		_was_planning = true
		return
	if _was_planning:
		_was_planning = false
		reset()
	_track_steps()
	if is_finished():
		return
	_idle += delta
	var quest := current()
	match phase:
		Phase.TRIGGER:
			if LOGIC.trigger_ready(quest, _trigger_context()):
				phase = Phase.DELAY
				_delay = float(quest.delay)
				if _delay <= 0.0:
					_activate()
		Phase.DELAY:
			_delay -= delta
			if _delay <= 0.0:
				_activate()
		Phase.ACTIVE:
			_message_left -= delta
			if _quest_done(quest):
				_finish_quest()


func _begin_quest() -> void:
	phase = Phase.TRIGGER
	_idle = 0.0
	_walked_at_start = _walked
	_mutation_last = _mutation()
	_mutation_rise = 0.0
	_targets = []
	_trigger_node = null
	if is_finished() or not is_inside_tree():
		return
	var quest := current()
	_trigger_node = BOOK.find_object(get_tree(), str(quest.trigger.target))
	_trigger_existed = _trigger_node != null


func _track_steps() -> void:
	var position := player.global_position
	if _last_position.is_finite():
		var moved := Vector2(position.x - _last_position.x, position.z - _last_position.z).length()
		if moved < TELEPORT:
			_walked += moved
	_last_position = position


func _steps_since_start() -> float:
	return (_walked - _walked_at_start) / LOGIC.STEP_METERS


func _trigger_context() -> Dictionary:
	var reach := INF
	var quest := current()
	if is_instance_valid(_trigger_node):
		reach = _flat(_trigger_node.global_position)
	elif quest.trigger.point is Array and (quest.trigger.point as Array).size() == 2:
		var point: Array = quest.trigger.point
		reach = _flat(Vector3(float(point[0]), 0.0, float(point[1])))
	return {"idle": _idle, "steps": _steps_since_start(), "reach": reach, "mutation_gain": _track_mutation(),
			"menu_open": _menu_open(), "control_lost": _control_lost(),
			"trigger_collected": _trigger_existed and not _alive(_trigger_node)}


func _track_mutation() -> float:
	var now := _mutation()
	_mutation_rise += maxf(0.0, now - _mutation_last)
	_mutation_last = now
	return _mutation_rise


func _mutation() -> float:
	var runtime: Variant = player.get("infection_runtime") if player != null else null
	return float(runtime.call("get_mutation")) if runtime != null else 0.0


func _control_lost() -> bool:
	var runtime: Variant = player.get("infection_runtime") if player != null else null
	return runtime != null and bool(runtime.call("is_control_lost"))


func _left_level() -> bool:
	var layout: Variant = host.get("mission_layout") if host != null else null
	return layout != null and bool(layout.call("goal_reached", player.global_position))


func _menu_open() -> bool:
	var menu: Variant = host.get("mutation_tree_ui") if host != null else null
	return menu != null and bool(menu.call("is_tree_open"))


func _flat(position: Vector3) -> float:
	return Vector2(position.x - player.global_position.x, position.z - player.global_position.z).length()


func _activate() -> void:
	phase = Phase.ACTIVE
	_walked_at_start = _walked
	var quest := current()
	_targets = []
	for id: String in quest.targets:
		var node := BOOK.find_object(get_tree(), id)
		if node != null:
			_targets.append(node)
	BOOK.show_markers(get_tree(), _targets)
	if bool(quest.get("pointer", false)):
		_point_floor(_pointer_target)
	match str(quest.type):
		"lesson":
			if director != null:
				director.call("play", str(quest.lesson), _targets)
		"message":
			_message_left = MESSAGE_SECONDS
			_set_objective(str(quest.text))
		_:
			_set_objective(str(quest.text))


func _quest_done(quest: Dictionary) -> bool:
	if str(quest.type) == "message":
		return _message_left <= 0.0
	if str(quest.type) == "leave":
		return LOGIC.complete(quest, {"left_level": _left_level()})
	var context := {"steps": _steps_since_start(), "distances": [], "gone": []}
	for node in _targets:
		var alive := _alive(node)
		(context.gone as Array).append(not alive)
		if alive:
			(context.distances as Array).append(_flat((node as Node3D).global_position))
	if str(quest.type) == "lesson":
		context["lesson_done"] = director == null or bool(director.call("is_finished", str(quest.lesson)))
	return LOGIC.complete(quest, context)


## Standing, alive and not yet taken.
func _alive(node: Variant) -> bool:
	if not is_instance_valid(node) or (node as Node).is_queued_for_deletion():
		return false
	if (node as Node).has_method("is_dead") and bool((node as Node).call("is_dead")):
		return false
	return TARGET.is_standing(node)


func _finish_quest() -> void:
	phase = Phase.DONE
	_point_floor(Callable())
	_set_objective("")
	BOOK.show_markers(get_tree(), [])
	index += 1
	_begin_quest()


## The floor chevrons lead to the nearest target still standing; an invalid callable turns them off.
func _point_floor(target: Callable) -> void:
	if host != null and host.has_method("set_tutorial_hint"):
		host.call("set_tutorial_hint", target)


func _pointer_target() -> Vector3:
	var best := Vector3.INF
	var best_distance := INF
	for node in _targets:
		if _alive(node):
			var distance := _flat((node as Node3D).global_position)
			if distance < best_distance:
				best_distance = distance
				var position := (node as Node3D).global_position
				best = Vector3(position.x, 0.0, position.z)
	return best


func _set_objective(text: String) -> void:
	_objective_text = text
	_show_objective()


func _show_objective() -> void:
	if hud != null:
		hud.call("set_tutorial_objective", MODEL.display_text(_objective_text))


# A language change re-reads the shown quest text, so the banner switches at once.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not _objective_text.is_empty():
		_show_objective()
