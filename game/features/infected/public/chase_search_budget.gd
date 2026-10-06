extends Node
## Mission-owned FIFO for expensive route searches. Requests hold weak refs only.
@export var searches_per_frame := 2
var searches_last_frame := 0
var total_searches := 0
var _queue: Array[Dictionary] = []
var _pending: Dictionary = {}


func request(route: RefCounted, actor: Node3D, target: Node3D) -> void:
	var id := route.get_instance_id()
	if not _pending.has(id):
		_queue.append({"id": id, "route": weakref(route)})
	_pending[id] = {"actor": weakref(actor), "target": weakref(target)}


func cancel(route: RefCounted) -> void:
	_pending.erase(route.get_instance_id())


func pending_count() -> int:
	return _pending.size()


func _physics_process(_delta: float) -> void:
	searches_last_frame = 0
	# Inspect only the requests present at the beginning of this tick.
	var remaining := _queue.size()
	while remaining > 0 and searches_last_frame < maxi(1, searches_per_frame):
		remaining -= 1
		var entry: Dictionary = _queue.pop_front()
		var route := entry.route.get_ref() as RefCounted
		if route == null:
			_pending.erase(entry.id)
			continue
		if not _pending.has(entry.id):
			continue
		var request_data: Dictionary = _pending[route.get_instance_id()]
		_pending.erase(route.get_instance_id())
		var actor := request_data.actor.get_ref() as CharacterBody3D
		var target := request_data.target.get_ref() as Node3D
		if actor == null or target == null or not actor.is_inside_tree() or not target.is_inside_tree():
			continue
		if actor.has_method("is_dead") and bool(actor.call("is_dead")):
			continue
		if bool(route.call("search_requested", actor, target)):
			searches_last_frame += 1
			total_searches += 1
