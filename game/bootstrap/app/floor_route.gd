extends RefCounted
## Walkable route for the floor arrows: A* on a 0.8 m grid whose cells are blocked by what the physics
## world says (walls, furniture), then pulled straight where the way is clear. Doors count as open, except
## sealed ones, because the player opens them on the way. Cell answers are cached for a few seconds.

const CELL := 0.8
const RADIUS := 0.32
const HEIGHT := 0.6
const MASK := 3
const MAX_EXPANSIONS := 3500
const MARGIN_CELLS := 24 # how far the search may leave the box around the start and the goal
const CACHE_MSEC := 4000
const SAMPLE_STEP := 0.4
const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

var _clear := {} # Vector2i -> bool
var _cache_from := 0
var _shape := SphereShape3D.new()
var _space: PhysicsDirectSpaceState3D
var _excluded: Array[RID] = []


## Points from near `from` to `goal` (world x/z, y 0), or an empty array when no way is found in budget.
func find(space: PhysicsDirectSpaceState3D, from: Vector3, goal: Vector3, excluded: Array[RID] = []) -> Array[Vector3]:
	_space = space
	_excluded = excluded
	_shape.radius = RADIUS
	if Time.get_ticks_msec() - _cache_from > CACHE_MSEC:
		_clear.clear()
		_cache_from = Time.get_ticks_msec()
	var start := _cell_of(from)
	var target := _cell_of(goal)
	var cells := _search(start, target)
	if cells.is_empty():
		return []
	return _pull_straight(cells, start, target, from, goal)


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / CELL), roundi(point.z / CELL))


func _center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL, 0.0, cell.y * CELL)


func _search(start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var low := Vector2i(mini(start.x, target.x), mini(start.y, target.y)) - Vector2i.ONE * MARGIN_CELLS
	var high := Vector2i(maxi(start.x, target.x), maxi(start.y, target.y)) + Vector2i.ONE * MARGIN_CELLS
	var best := {start: 0.0}
	var came := {}
	var open: Array = [[_heuristic(start, target), start]] # a binary min-heap on the first element
	var closed := {}
	var expansions := 0
	while not open.is_empty() and expansions < MAX_EXPANSIONS:
		var cell: Vector2i = _pop(open)[1]
		if cell == target:
			return _unwind(came, cell)
		if closed.has(cell):
			continue
		closed[cell] = true
		expansions += 1
		for step in STEPS:
			var next := cell + step
			if closed.has(next) or next.x < low.x or next.y < low.y or next.x > high.x or next.y > high.y:
				continue
			if next != target and not _cell_clear(next):
				continue
			var diagonal := step.x != 0 and step.y != 0
			# No cutting a corner: both cells beside a diagonal step must be free as well.
			if diagonal and not (_cell_clear(cell + Vector2i(step.x, 0)) and _cell_clear(cell + Vector2i(0, step.y))):
				continue
			var cost: float = float(best[cell]) + (1.4142 if diagonal else 1.0)
			if not best.has(next) or cost < float(best[next]):
				best[next] = cost
				came[next] = cell
				_push(open, [cost + _heuristic(next, target), next])
	return []


func _heuristic(from: Vector2i, to: Vector2i) -> float:
	var dx := absi(from.x - to.x)
	var dy := absi(from.y - to.y)
	return float(maxi(dx, dy)) + 0.4142 * float(mini(dx, dy))


func _unwind(came: Dictionary, last: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [last]
	while came.has(last):
		last = came[last]
		cells.push_front(last)
	return cells


## Drops waypoints the straight line can skip, so the arrows follow corridors and corners, not the grid.
func _pull_straight(cells: Array[Vector2i], _start: Vector2i, _target: Vector2i, from: Vector3, goal: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var anchor := from
	var index := 0
	while index < cells.size() - 1:
		var farthest := index + 1
		for later in range(cells.size() - 1, index, -1):
			if _line_clear(anchor, _center(cells[later])):
				farthest = later
				break
		points.append(_center(cells[farthest]))
		anchor = _center(cells[farthest])
		index = farthest
	if points.is_empty() or points[-1].distance_to(goal) > 0.01:
		points.append(Vector3(goal.x, 0.0, goal.z))
	return points


func _line_clear(a: Vector3, b: Vector3) -> bool:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var count := ceili(length / SAMPLE_STEP)
	for i in range(1, count):
		if not _cell_clear(_cell_of(a.lerp(b, float(i) / float(count)))):
			return false
	return true


func _cell_clear(cell: Vector2i) -> bool:
	if _clear.has(cell):
		return _clear[cell]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(cell.x * CELL, HEIGHT, cell.y * CELL))
	query.collision_mask = MASK
	query.exclude = _excluded
	var free := true
	for hit in _space.intersect_shape(query, 8):
		if not _is_open_door(hit.get("collider")):
			free = false
			break
	_clear[cell] = free
	return free


## The collider belongs to a door that the player can open (a sealed one never opens).
func _is_open_door(collider: Variant) -> bool:
	var node := collider as Node
	for _level in 4:
		if node == null:
			return false
		if node.has_method("get_lock_state"):
			return str(node.call("get_lock_state")) != "sealed"
		node = node.get_parent()
	return false


func _push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var child := heap.size() - 1
	while child > 0:
		@warning_ignore("integer_division")
		var parent := (child - 1) / 2
		if float(heap[parent][0]) <= float(heap[child][0]):
			break
		var swap: Array = heap[parent]
		heap[parent] = heap[child]
		heap[child] = swap
		child = parent


func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var parent := 0
		while true:
			var left := parent * 2 + 1
			var right := left + 1
			var smallest := parent
			if left < heap.size() and float(heap[left][0]) < float(heap[smallest][0]):
				smallest = left
			if right < heap.size() and float(heap[right][0]) < float(heap[smallest][0]):
				smallest = right
			if smallest == parent:
				break
			var swap: Array = heap[parent]
			heap[parent] = heap[smallest]
			heap[smallest] = swap
			parent = smallest
	return top
