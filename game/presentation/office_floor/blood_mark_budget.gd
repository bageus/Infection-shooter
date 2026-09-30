extends Node3D

const MARK := preload("res://game/presentation/office_floor/blood_mark_3d.gd")
const SURFACES := preload("res://game/presentation/office_floor/blood_surface_query.gd")

var max_marks := 128
var per_surface_limit := 0
var lifetime := 90.0
var fade_seconds := 1.2
var settings: Dictionary = {}
var container: Node3D
var _clock := 0.0
var _next_id := 0
var _records: Dictionary = {}
var _pending: Array[Dictionary] = []
var _deaths: Array[Dictionary] = []
var _death_ids: Dictionary = {}


func _ready() -> void:
	container = Node3D.new()
	container.name = "BloodMarks"
	add_child(container)
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	timer.timeout.connect(_maintenance)
	add_child(timer)
	timer.start()


func submit(definition: Dictionary, surface: Dictionary) -> void:
	if definition.is_empty() or SURFACES.resolve(surface).is_empty():
		return
	if not _admit(definition, surface):
		if _pending.size() >= 16:
			_pending.pop_front()
		_pending.append({"definition": definition, "surface": surface, "until": _clock + 3.0})


func schedule_pool(death_id: int, definition: Dictionary, surface: Dictionary, delay: float) -> void:
	if _death_ids.has(death_id):
		return
	_death_ids[death_id] = true
	if not definition.is_empty() and not surface.is_empty():
		_deaths.append({"definition": definition, "surface": surface, "due": _clock + delay})


func _admit(definition: Dictionary, surface: Dictionary) -> bool:
	var hit := SURFACES.resolve(surface)
	if hit.is_empty():
		return true
	var body: Node3D = hit["collider"]
	var key := body.get_instance_id()
	var count := 0
	var victim := -1
	var surface_fading := 0
	var total_fading := 0
	for id in _records:
		if _records[id]["fading"]:
			total_fading += 1
		if _records[id]["key"] == key:
			if _records[id]["fading"]:
				surface_fading += 1
			count += 1
			if victim < 0 and not _records[id]["fading"]:
				victim = id
	if per_surface_limit > 0 and count >= per_surface_limit:
		if victim >= 0 and surface_fading == 0:
			_retire(victim)
		return false
	if _records.size() >= maxi(max_marks, 1):
		for id in _records:
			if not _records[id]["fading"] and total_fading < mini(8, _pending.size() + 1):
				_retire(id)
				break
		return false
	var mark := MARK.new() as Node3D
	container.add_child(mark)
	var render_definition := definition.duplicate()
	if render_definition.has("local_basis"):
		render_definition["basis"] = (body.global_basis * render_definition["local_basis"]).orthonormalized()
	mark.call("configure", hit, render_definition, settings)
	_next_id += 1
	_records[_next_id] = {"mark": weakref(mark), "key": key, "expires": _clock + lifetime, "fading": false}
	return true


func _maintenance() -> void:
	_clock += 0.1
	for request in _deaths.duplicate():
		if request["due"] <= _clock:
			submit(request["definition"], request["surface"])
			_deaths.erase(request)
	for id in _records.keys():
		var mark := (_records[id]["mark"] as WeakRef).get_ref() as Node3D
		if mark == null:
			_remove(id)
		elif not _surface_alive(mark):
			_remove(id)
		elif _records[id]["expires"] <= _clock:
			_retire(id)
	for request in _pending.duplicate():
		if request["until"] < _clock or _admit(request["definition"], request["surface"]):
			_pending.erase(request)


func _surface_alive(mark: Node3D) -> bool:
	var surface := (mark.get("surface_ref") as WeakRef).get_ref() as Node3D
	return surface != null and surface.is_inside_tree() and not surface.is_queued_for_deletion()


func _retire(id: int) -> void:
	if not _records.has(id) or _records[id]["fading"]:
		return
	var mark := (_records[id]["mark"] as WeakRef).get_ref() as Node3D
	if mark == null:
		_remove(id)
		return
	_records[id]["fading"] = true
	mark.call("fade_out", fade_seconds, _remove.bind(id))


func _remove(id: int) -> void:
	if not _records.has(id):
		return
	var mark := (_records[id]["mark"] as WeakRef).get_ref() as Node3D
	if mark != null:
		container.remove_child(mark)
		mark.queue_free()
	_records.erase(id)


func clear_marks() -> void:
	_pending.clear()
	_deaths.clear()
	_death_ids.clear()
	for id in _records.keys():
		_remove(id)


func statistics() -> Dictionary:
	return {"marks": _records.size(), "pending": _pending.size(), "pending_pools": _deaths.size()}
