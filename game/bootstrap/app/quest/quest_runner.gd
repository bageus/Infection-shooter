extends Node
## Plays the map's quests one after another: wait for the trigger, wait the delay, show the task,
## wait for its completion, then move on to the next. Nothing starts while the planner is open.

const LOGIC := preload("res://game/bootstrap/app/quest/quest_logic.gd")
const BOOK := preload("res://game/bootstrap/app/quest/quest_book.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const MESSAGE_SECONDS := 6.0
const TELEPORT := 3.0

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
var _trigger_node: Node3D
var _was_planning := false


func configure(quest_book: Node, hero: Node3D, interface: Node, lessons: Node, owner_node: Node) -> void:
	book = quest_book
	player = hero
	hud = interface
	director = lessons
	host = owner_node
	book.changed.connect(reset)


func reset() -> void:
	index = 0
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
	if player == null or book == null:
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
	_targets = []
	_trigger_node = null
	if is_finished() or not is_inside_tree():
		return
	var quest := current()
	_trigger_node = BOOK.find_object(get_tree(), str(quest.trigger.target))


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
	return {"idle": _idle, "steps": _steps_since_start(), "reach": reach}


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
	match str(quest.type):
		"lesson":
			if director != null:
				director.call("play", str(quest.lesson))
		"message":
			_message_left = MESSAGE_SECONDS
			_set_objective(str(quest.text))
		_:
			_set_objective(str(quest.text))


func _quest_done(quest: Dictionary) -> bool:
	if str(quest.type) == "message":
		return _message_left <= 0.0
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
	_set_objective("")
	BOOK.show_markers(get_tree(), [])
	index += 1
	_begin_quest()


func _set_objective(text: String) -> void:
	if hud != null:
		hud.call("set_tutorial_objective", text)
