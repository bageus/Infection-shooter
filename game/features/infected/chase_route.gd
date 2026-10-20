extends RefCounted
## Bounded local A*: paths use actual physics clearance and never disable walls.
const HEAP := preload("res://game/features/infected/route_priority_queue.gd")
const CELL := .8
## Mission-wide cap on clearance sweeps made by moving enemies per physics frame, so a crowd
## cannot push one step past the frame budget. Searches have their own budget node.
const DIRECT_PROBES_PER_FRAME := 10
const PATH_PROBES_PER_FRAME := 16
## A direct check this overdue runs regardless of the cap, so no enemy starves.
const MAX_PROBE_DELAY := 12
static var _probe_frame := -1
static var _direct_used := 0
static var _path_used := 0
const MAX_EXPANSIONS := 192
const SEARCH_RADIUS := 18
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
var path: Array[Vector3] = []
var _next_search := 0
var _next_probe := 0
var _denied_since := -1
var _direct := true
var _goal := Vector3.INF
var _radius := .35
var _space: PhysicsDirectSpaceState3D
var _excluded: Array[RID] = []
var _shape := SphereShape3D.new()
var _height := 1.0
var _budget: Node
var _search_state: Dictionary = {}
var _clearance_cache: Dictionary = {}
var _cache_frame := -1
var probes_last_slice := 0
var expansions_last_slice := 0


func configure_budget(budget: Node) -> void:
	if is_instance_valid(_budget):
		_budget.call("cancel", self)
	_budget = budget


## A far enemy is out of sight and ticks rarely: it heads straight for the target and plans
## around walls (physics sweeps, A*) only once it is inside the enemy's sleep distance.
func direction(actor: CharacterBody3D, target: Node3D, radius: float, far: bool = false) -> Vector3:
	if far:
		if not path.is_empty() or _next_probe != 0:
			release()
		var offset := target.global_position - actor.global_position
		offset.y = 0.0
		return offset.normalized()
	var frame := Engine.get_physics_frames()
	_space = actor.get_world_3d().direct_space_state
	_excluded = [actor.get_rid()]
	if target is CollisionObject3D:
		_excluded.append((target as CollisionObject3D).get_rid())
	_radius = maxf(radius, .15)
	_shape.radius = _radius
	_height = actor.global_position.y
	var from := actor.global_position
	var to := target.global_position
	to.y = _height
	# Close to the target the direct-line answer must be fresh, so a swing is never held back.
	# Beyond 10 m walls are not probed: head straight, plan around them once inside that range.
	if from.distance_squared_to(to) > 100.0:
		_direct = true
	elif (frame >= _next_probe or from.distance_squared_to(to) < 9.0) and _take_direct_probe(frame):
		_next_probe = frame + 6
		_direct = clear_segment(from, to)
	if _direct:
		if is_instance_valid(_budget):
			_budget.call("cancel", self)
		path.clear()
		return (to - from).normalized()
	# A completed search owns the retry clock, including stale/blocked paths.
	if frame >= _next_search:
		if is_instance_valid(_budget):
			_budget.call("request", self, actor, target)
		else:
			search_requested(actor, target)
	while not path.is_empty() and from.distance_to(path[0]) < .28:
		path.pop_front()
	if path.is_empty():
		return Vector3.ZERO
	# Skip intermediate cells only when the actor's whole width fits.
	var shortcuts := 0
	while path.size() > 1 and shortcuts < 4 and _take_path_probe(frame) and clear_segment(from, path[1]):
		shortcuts += 1
		path.pop_front()
	# Over the cap the next waypoint is trusted; the capsule still stops at walls.
	if _take_path_probe(frame) and not clear_segment(from, path[0]):
		# Stop at the obstacle, but retain the normal retry cooldown.
		return Vector3.ZERO
	return (path[0] - from).normalized()


func _roll_probe_frame(frame: int) -> void:
	if frame != _probe_frame:
		_probe_frame = frame
		_direct_used = 0
		_path_used = 0


func _take_direct_probe(frame: int) -> bool:
	if not is_instance_valid(_budget):
		return true
	_roll_probe_frame(frame)
	if _direct_used >= DIRECT_PROBES_PER_FRAME:
		if _denied_since < 0:
			_denied_since = frame
		if frame - _denied_since < MAX_PROBE_DELAY:
			return false
	_denied_since = -1
	_direct_used += 1
	return true


func _take_path_probe(frame: int) -> bool:
	if not is_instance_valid(_budget):
		return true
	_roll_probe_frame(frame)
	if _path_used >= PATH_PROBES_PER_FRAME:
		return false
	_path_used += 1
	return true


## Drops the queued search and the stored path of an actor that no longer steers around walls.
func release() -> void:
	if is_instance_valid(_budget):
		_budget.call("cancel", self)
	path.clear()
	_search_state.clear()
	_direct = true
	_next_probe = 0
	_denied_since = -1
	_next_search = 0


func search_requested(actor: CharacterBody3D, target: Node3D) -> bool:
	# Standalone fixtures keep synchronous compatibility; missions use slices.
	begin_search(actor, target)
	var blocked := not _direct
	while not _search_state.is_empty():
		step_search(0, MAX_EXPANSIONS)
	return blocked


func begin_search(actor: CharacterBody3D, target: Node3D) -> void:
	_space = actor.get_world_3d().direct_space_state
	_excluded = [actor.get_rid()]
	if target is CollisionObject3D:
		_excluded.append((target as CollisionObject3D).get_rid())
	_height = actor.global_position.y
	var from := actor.global_position
	var to := target.global_position
	to.y = _height
	_direct = from.distance_squared_to(to) > 100.0 or clear_segment(from, to)
	_search_state.clear()
	if _direct:
		path.clear()
		return
	var start := _cell(from)
	var goal := _cell(to)
	var heap := HEAP.new()
	heap.push({"cell": start, "cost": 0.0}, _heuristic(start, goal))
	_search_state = {"from": from, "to": to, "height": _height, "cooldown": 45 + int(actor.get_instance_id() % 20), "start": start, "goal": goal,
		"open": heap, "cost": {start: 0.0}, "parents": {}, "closed": {},
		"best": start, "best_distance": _heuristic(start, goal), "count": 0,
		"current": {}, "offset": 0}


func cancel_search() -> void:
	_search_state.clear()


func step_search(deadline_usec: int, max_expansions: int = 4) -> bool:
	probes_last_slice = 0
	expansions_last_slice = 0
	if _search_state.is_empty():
		return true
	var state := _search_state
	_height = float(state.height)
	while deadline_usec == 0 or Time.get_ticks_usec() < deadline_usec:
		if state.current.is_empty():
			if state.count >= MAX_EXPANSIONS or state.open.entries.is_empty():
				return _finish_search(state)
			if expansions_last_slice >= max_expansions:
				return false
			var entry: Dictionary = state.open.pop()
			var cell: Vector2i = entry.cell
			if state.closed.has(cell) or float(entry.cost) != float(state.cost.get(cell, INF)):
				continue
			state.closed[cell] = true
			state.current = entry
			state.offset = 0
			state.count += 1
			expansions_last_slice += 1
			var distance := _heuristic(cell, state.goal)
			if distance < float(state.best_distance):
				state.best = cell
				state.best_distance = distance
			if cell == state.goal:
				state.best = cell
				return _finish_search(state)
		if int(state.offset) >= DIRECTIONS.size():
			state.current = {}
			continue
		_expand_neighbor(state)
	return false


func _expand_neighbor(state: Dictionary) -> void:
	var current: Vector2i = state.current.cell
	var offset: Vector2i = DIRECTIONS[int(state.offset)]
	state.offset += 1
	var next := current + offset
	var start: Vector2i = state.start
	if state.closed.has(next) or absi(next.x - start.x) > SEARCH_RADIUS or absi(next.y - start.y) > SEARCH_RADIUS:
		return
	var next_cost := float(state.cost[current]) + Vector2(offset).length()
	if next_cost >= float(state.cost.get(next, INF)):
		return
	var a: Vector3 = state.from if current == start else _point(current)
	if not clear_segment(a, _point(next)):
		return
	state.cost[next] = next_cost
	state.parents[next] = current
	state.open.push({"cell": next, "cost": next_cost}, next_cost + _heuristic(next, state.goal))


func _finish_search(state: Dictionary) -> bool:
	path = _trace(state.parents, state.best, state.start)
	_goal = state.to
	_next_search = Engine.get_physics_frames() + int(state.cooldown)
	_search_state = {}
	return true


func clear_segment(from: Vector3, to: Vector3) -> bool:
	var frame := Engine.get_physics_frames()
	# Obstacles only move in the physics step, so answers hold for the whole frame.
	if frame != _cache_frame:
		_cache_frame = frame
		_clearance_cache.clear()
	var key := [from, to, _radius]
	if _clearance_cache.has(key):
		return _clearance_cache[key]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform.origin = from
	query.motion = to - from
	query.collision_mask = 1
	query.exclude = _excluded
	query.margin = .02
	var motion := _space.cast_motion(query)
	probes_last_slice += 1
	var clear := not motion.is_empty() and motion[0] >= .999
	_clearance_cache[key] = clear
	return clear


func direct_clear() -> bool:
	return _direct


func _trace(parents: Dictionary, goal: Vector2i, start: Vector2i) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var cell := goal
	while cell != start and parents.has(cell):
		result.push_front(_point(cell))
		cell = parents[cell]
	return result


func _cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / CELL), roundi(point.z / CELL))


func _point(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL, _height, cell.y * CELL)


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()
