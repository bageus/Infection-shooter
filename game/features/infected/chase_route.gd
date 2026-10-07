extends RefCounted
## Bounded local A*: paths use actual physics clearance and never disable walls.
const CELL := .8
const MAX_EXPANSIONS := 192
const SEARCH_RADIUS := 18
const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
var path: Array[Vector3] = []
var _next_search := 0
var _next_probe := 0
var _direct := true
var _goal := Vector3.INF
var _radius := .35
var _space: PhysicsDirectSpaceState3D
var _excluded: Array[RID] = []
var _shape := SphereShape3D.new()
var _height := 1.0
var _budget: Node


func configure_budget(budget: Node) -> void:
	if is_instance_valid(_budget):
		_budget.call("cancel", self)
	_budget = budget


func direction(actor: CharacterBody3D, target: Node3D, radius: float) -> Vector3:
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
	if frame >= _next_probe:
		_next_probe = frame + 6
		_direct = clear_segment(from, to)
	if _direct:
		if is_instance_valid(_budget):
			_budget.call("cancel", self)
		path.clear()
		return (to - from).normalized()
	if frame >= _next_search or _goal.distance_squared_to(to) > 2.0:
		if is_instance_valid(_budget):
			_budget.call("request", self, actor, target)
		else:
			search_requested(actor, target)
	while not path.is_empty() and from.distance_to(path[0]) < .28:
		path.pop_front()
	if path.is_empty():
		return Vector3.ZERO
	# Skip intermediate cells only when the actor's whole width fits.
	while path.size() > 1 and clear_segment(from, path[1]):
		path.pop_front()
	if not clear_segment(from, path[0]):
		_next_search = 0
		return Vector3.ZERO
	return (path[0] - from).normalized()


func search_requested(actor: CharacterBody3D, target: Node3D) -> bool:
	# The target can move while queued; search from the current positions.
	_space = actor.get_world_3d().direct_space_state
	_excluded = [actor.get_rid()]
	if target is CollisionObject3D:
		_excluded.append((target as CollisionObject3D).get_rid())
	_height = actor.global_position.y
	var from := actor.global_position
	var to := target.global_position
	to.y = _height
	_next_search = Engine.get_physics_frames() + 45 + int(actor.get_instance_id() % 20)
	_goal = to
	_direct = clear_segment(from, to)
	# A typed empty literal: the ternary form yields an untyped Array.
	path = []
	if not _direct:
		path = _search(from, to)
	return not _direct


func clear_segment(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform.origin = from
	query.motion = to - from
	query.collision_mask = 1
	query.exclude = _excluded
	query.margin = .02
	var motion := _space.cast_motion(query)
	return not motion.is_empty() and motion[0] >= .999


func direct_clear() -> bool:
	return _direct


func _search(from: Vector3, to: Vector3) -> Array[Vector3]:
	var start := _cell(from)
	var goal := _cell(to)
	var open: Array[Vector2i] = [start]
	var cost: Dictionary = {start: 0.0}
	var parents: Dictionary = {}
	var closed: Dictionary = {}
	var best := start
	var best_distance := _heuristic(start, goal)
	for _expansion in range(MAX_EXPANSIONS):
		if open.is_empty():
			break
		var index := _lowest(open, cost, goal)
		var current := open[index]
		open.remove_at(index)
		closed[current] = true
		var distance := _heuristic(current, goal)
		if distance < best_distance:
			best = current
			best_distance = distance
		if current == goal:
			return _trace(parents, current, start)
		for offset in DIRECTIONS:
			var next := current + offset
			if closed.has(next) or absi(next.x - start.x) > SEARCH_RADIUS or absi(next.y - start.y) > SEARCH_RADIUS:
				continue
			var next_cost := float(cost[current]) + Vector2(offset).length()
			if next_cost >= float(cost.get(next, INF)):
				continue
			var a := from if current == start else _point(current)
			if not clear_segment(a, _point(next)):
				continue
			cost[next] = next_cost
			parents[next] = current
			if not open.has(next):
				open.append(next)
	return _trace(parents, best, start)


func _trace(parents: Dictionary, goal: Vector2i, start: Vector2i) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var cell := goal
	while cell != start and parents.has(cell):
		result.push_front(_point(cell))
		cell = parents[cell]
	return result


func _lowest(open: Array[Vector2i], cost: Dictionary, goal: Vector2i) -> int:
	var best := 0
	var lowest := INF
	for i in range(open.size()):
		var score := float(cost[open[i]]) + _heuristic(open[i], goal)
		if score < lowest:
			lowest = score
			best = i
	return best


func _cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / CELL), roundi(point.z / CELL))


func _point(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL, _height, cell.y * CELL)


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()
