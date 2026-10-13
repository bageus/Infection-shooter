extends Node3D

const MARK := preload("res://game/presentation/office_floor/blood_mark_3d.gd")
const SURFACES := preload("res://game/presentation/office_floor/blood_surface_query.gd")
const FIFO := preload("res://game/presentation/office_floor/blood_mark_fifo.gd")

var max_marks := 128
var per_surface_limit := 0
## 0 keeps a mark until the budget needs its slot.
var lifetime := 0.0
## Marks farther than unload_distance from the camera leave the scene tree and
## wait as data in _dormant; they come back once the camera is within load_distance.
var unload_distance := 30.0
var load_distance := 22.0
var dormant_limit := 400
const RELOADS_PER_TICK := 4
var fade_seconds := 1.2
var settings: Dictionary = {}
var container: Node3D
var _clock := 0.0
var _next_id := 0
var _records: Dictionary = {}
var _pending: Array[Dictionary] = []
var _deaths: Array[Dictionary] = []
var _death_ids: Dictionary = {}
var _surfaces: Dictionary = {}
var _active := FIFO.new()
var _fading := 0
var _dormant: Array[Dictionary] = []
var _camera_point := Vector3.ZERO
var _has_camera := false
var _timer: Timer


func _ready() -> void:
	container = Node3D.new()
	container.name = "BloodMarks"
	add_child(container)
	_timer = Timer.new()
	_timer.wait_time = 0.1
	_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	_timer.timeout.connect(_maintenance)
	add_child(_timer)


func submit(definition: Dictionary, surface: Dictionary) -> void:
	if definition.is_empty() or SURFACES.resolve(surface).is_empty():
		return
	if not _admit(definition, surface):
		if _pending.size() >= 16:
			_pending.pop_front()
		_pending.append({"definition": definition, "surface": surface, "until": _clock + 3.0})
	_wake()


func schedule_pool(death_id: int, definition: Dictionary, surface: Dictionary, delay: float) -> void:
	if _death_ids.has(death_id):
		return
	_death_ids[death_id] = true
	if not definition.is_empty() and not surface.is_empty():
		if get_tree().paused:
			# Game-over freezes simulation; still show the already reported death.
			definition = definition.duplicate()
			definition["pool"] = false
			_admit(definition, surface)
			return
		_deaths.append({"definition": definition, "surface": surface, "due": _clock + delay})
		_wake()


func _admit(definition: Dictionary, surface: Dictionary, evict: bool = true) -> bool:
	var hit := SURFACES.resolve(surface)
	if hit.is_empty():
		return true
	var body: Node3D = hit["collider"]
	var key := body.get_instance_id()
	var state: Dictionary = _surfaces[key] if _surfaces.has(key) else {"count": 0, "fading": 0, "active": FIFO.new()}
	if per_surface_limit > 0 and state["count"] >= per_surface_limit:
		if evict and state["active"].first >= 0 and state["fading"] == 0:
			_retire(state["active"].first)
		return false
	if _records.size() >= maxi(max_marks, 1):
		if evict and _active.first >= 0 and _fading < mini(8, _pending.size() + 1):
			_retire(_active.first)
		return false
	var mark := MARK.new() as Node3D
	container.add_child(mark)
	var render_definition := definition.duplicate()
	if render_definition.has("local_basis"):
		render_definition["basis"] = (body.global_basis * render_definition["local_basis"]).orthonormalized()
	if not mark.call("configure", hit, render_definition, settings):
		# An unsupported projection is not a rendered mark and consumes no budget.
		mark.free()
		return true
	_next_id += 1
	var expires := _clock + lifetime if lifetime > 0.0 else INF
	_records[_next_id] = {"mark": weakref(mark), "key": key, "expires": expires, "fading": false, "definition": definition, "surface": surface, "position": hit["position"]}
	state["count"] += 1
	state["active"].append(_next_id)
	_surfaces[key] = state
	_active.append(_next_id)
	_wake()
	return true


func _maintenance() -> void:
	_clock += 0.1
	_read_camera()
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
		elif _has_camera and not _records[id]["fading"] and _camera_point.distance_to(_records[id]["position"]) > unload_distance:
			_unload(id)
	for request in _pending.duplicate():
		if request["until"] < _clock or _admit(request["definition"], request["surface"]):
			_pending.erase(request)
	_reload_near_dormant()
	_sleep_if_empty()


func _read_camera() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	_has_camera = camera != null
	if _has_camera:
		_camera_point = camera.global_position


# Frees a far mark but keeps what is needed to draw it again later.
func _unload(id: int) -> void:
	var record: Dictionary = _records[id]
	_dormant.append({"definition": record["definition"], "surface": record["surface"], "position": record["position"]})
	if _dormant.size() > dormant_limit:
		_dormant.pop_front()
	_remove(id)


func _reload_near_dormant() -> void:
	if not _has_camera or _dormant.is_empty():
		return
	var reloaded := 0
	for entry in _dormant.duplicate():
		if reloaded >= RELOADS_PER_TICK:
			break
		if _camera_point.distance_to(entry["position"]) > load_distance:
			continue
		if _admit(entry["definition"], entry["surface"], false):
			_dormant.erase(entry)
			reloaded += 1


func _wake() -> void:
	if _timer != null and _timer.is_stopped():
		_timer.start()


func _sleep_if_empty() -> void:
	if _timer != null and _records.is_empty() and _pending.is_empty() and _deaths.is_empty() and _dormant.is_empty():
		_timer.stop()


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
	var state: Dictionary = _surfaces[_records[id]["key"]]
	state["fading"] += 1
	_fading += 1
	state["active"].remove(id)
	_active.remove(id)
	mark.call("fade_out", fade_seconds, _remove.bind(id))


func _remove(id: int) -> void:
	if not _records.has(id):
		return
	var key: int = _records[id]["key"]
	var state: Dictionary = _surfaces[key]
	state["count"] -= 1
	if _records[id]["fading"]:
		state["fading"] -= 1
		_fading -= 1
	state["active"].remove(id)
	_active.remove(id)
	if state["count"] == 0:
		_surfaces.erase(key)
	var mark := (_records[id]["mark"] as WeakRef).get_ref() as Node3D
	if mark != null:
		container.remove_child(mark)
		mark.queue_free()
	_records.erase(id)
	_sleep_if_empty()


func clear_marks() -> void:
	_pending.clear()
	_deaths.clear()
	_death_ids.clear()
	_dormant.clear()
	for id in _records.keys():
		_remove(id)
	_sleep_if_empty()


func statistics() -> Dictionary:
	return {"marks": _records.size(), "pending": _pending.size(), "pending_pools": _deaths.size(), "dormant": _dormant.size()}
