extends Node
## Mission-local camera-prioritised preparation: one rig phase per frame.
const PREPARATION := preload("res://game/features/infected/infected_visual_preparation.gd")
const SCAN_LIMIT := 64
const PREPARE_DISTANCE := 40.0
var camera: Node3D
var phases_completed := 0
var max_phase_usec := 0
var _pending: Array[Dictionary] = []
var _cursor := 0
var _known := {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func track(actor: Node3D) -> void:
	if actor.has_meta("visual_parts_prepared"):
		return
	var id := actor.get_instance_id()
	if _known.has(id) and _known[id].get_ref() == actor:
		return
	_known[id] = weakref(actor)
	_pending.append({"actor": weakref(actor), "phase": 0, "id": id})
	var driver := actor.get_node_or_null("AnimationDriver")
	if driver != null and not driver.is_node_ready():
		driver.set("defer_setup", true)
		for animator in actor.find_children("*", "AnimationPlayer", true, false):
			(animator as AnimationPlayer).active = false


func _process(_delta: float) -> void:
	if not is_instance_valid(camera) or _pending.is_empty():
		return
	var best := -1
	var distance := PREPARE_DISTANCE * PREPARE_DISTANCE
	for scan in mini(SCAN_LIMIT, _pending.size()):
		_cursor %= _pending.size()
		var candidate: Node3D = _pending[_cursor].actor.get_ref()
		if not is_instance_valid(candidate) or candidate.has_meta("visual_parts_prepared"):
			_known.erase(_pending[_cursor].id)
			_pending.remove_at(_cursor)
			return
		var offset := Vector2(candidate.global_position.x - camera.global_position.x, candidate.global_position.z - camera.global_position.z) if candidate.is_inside_tree() else Vector2.INF
		if candidate.is_node_ready() and offset.length_squared() <= distance:
			distance = offset.length_squared()
			best = _cursor
		_cursor += 1
	if best < 0:
		return
	var entry: Dictionary = _pending[best]
	var actor: Node = entry.actor.get_ref()
	var started := Time.get_ticks_usec()
	if entry.phase == 0:
		PREPARATION.animation(actor)
		entry.phase = 1
	else:
		PREPARATION.parts(actor)
		_known.erase(entry.id)
		_pending.remove_at(best)
	phases_completed += 1
	max_phase_usec = maxi(max_phase_usec, Time.get_ticks_usec() - started)
