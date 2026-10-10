extends Node
## Mission-owned priority queue; bounded incremental search work per physics tick.
const HEAP := preload("res://game/features/infected/route_priority_queue.gd")
@export var searches_per_frame := 2
@export var time_budget_usec := 2000
@export var expansions_per_frame := 64
var searches_last_frame := 0
var total_searches := 0
var elapsed_last_frame_usec := 0
var expansions_last_frame := 0
var _queue := HEAP.new()
var _pending: Dictionary = {}
var _ticket := 0


func request(route: RefCounted, actor: Node3D, target: Node3D) -> void:
	var id := route.get_instance_id()
	if _pending.has(id):
		_pending[id].actor = weakref(actor)
		_pending[id].target = weakref(target)
		return
	_ticket += 1
	var entry := {"id": id, "ticket": _ticket, "route": weakref(route),
		"actor": weakref(actor), "target": weakref(target), "started": false}
	_pending[id] = entry
	_enqueue(entry, actor, target)


func _enqueue(entry: Dictionary, actor: Node3D, target: Node3D) -> void:
	# Nearby threats first; age outranks distance as a request waits.
	var score := minf(actor.global_position.distance_to(target.global_position), 100.0) + float(Engine.get_physics_frames()) * .5
	_queue.push(entry, score)


func cancel(route: RefCounted) -> void:
	_pending.erase(route.get_instance_id())
	route.call("cancel_search")
	if _pending.is_empty():
		_queue.entries.clear()
	elif _queue.entries.size() > maxi(64, _pending.size() * 2):
		_compact()


func pending_count() -> int:
	return _pending.size()


func _physics_process(_delta: float) -> void:
	searches_last_frame = 0
	expansions_last_frame = 0
	var started := Time.get_ticks_usec()
	var deadline := started + maxi(1, time_budget_usec)
	while not _queue.entries.is_empty() and searches_last_frame < maxi(1, searches_per_frame) and expansions_last_frame < maxi(1, expansions_per_frame) and Time.get_ticks_usec() < deadline:
		_service(deadline)
	elapsed_last_frame_usec = Time.get_ticks_usec() - started


func _service(deadline: int) -> void:
	var entry: Dictionary = _queue.pop()
	if not _pending.has(entry.id) or _pending[entry.id].ticket != entry.ticket:
		return
	entry.actor = _pending[entry.id].actor
	entry.target = _pending[entry.id].target
	var route := entry.route.get_ref() as RefCounted
	var actor := entry.actor.get_ref() as CharacterBody3D
	var target := entry.target.get_ref() as Node3D
	if route == null or actor == null or target == null or not actor.is_inside_tree() or not target.is_inside_tree() or (actor.has_method("is_dead") and bool(actor.call("is_dead"))):
		_pending.erase(entry.id)
		if route != null:
			route.call("cancel_search")
		return
	if entry.started and (actor.global_position.distance_squared_to(entry.origin) > .64 or target.global_position.distance_squared_to(entry.goal) > 2.0):
		entry.started = false
	if not entry.started:
		entry.origin = actor.global_position
		entry.goal = target.global_position
		route.call("begin_search", actor, target)
		entry.started = true
	var done: bool = route.call("step_search", deadline, mini(4, maxi(1, expansions_per_frame) - expansions_last_frame))
	expansions_last_frame += int(route.get("expansions_last_slice"))
	if done:
		_pending.erase(entry.id)
		searches_last_frame += 1
		total_searches += 1
	else:
		_pending[entry.id] = entry
		_enqueue(entry, actor, target)


func _compact() -> void:
	_queue.entries.clear()
	for id: int in _pending.keys():
		var entry: Dictionary = _pending[id]
		var actor := entry.actor.get_ref() as Node3D
		var target := entry.target.get_ref() as Node3D
		if actor == null or target == null or entry.route.get_ref() == null:
			_pending.erase(id)
		else:
			_enqueue(entry, actor, target)
