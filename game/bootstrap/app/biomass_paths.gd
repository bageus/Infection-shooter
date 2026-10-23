extends RefCounted
## Routes for the generated biomass (ADR-0062): an eight-way A* over a grid of
## half-metre cells that skips solid cells and the edge of the level, with a
## wandering cost so the route winds instead of running straight, then a smooth
## curve through it. Pure geometry: solid cells come from a callable.

const STEP := 0.5
## Cells within this distance of the level edge are solid: mass keeps off it.
const EDGE_MARGIN := 0.4
const SOLID_COST := 40.0
const WINDOW_MARGIN := 10.0
## A route this much longer than the straight line counts as winding.
const MIN_WIND := 1.18
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var level: Rect2
var columns := 0
var rows := 0
var _solid: Callable
var _cache := {}
var _noise := FastNoiseLite.new()
var _salt := 0


## level: world XZ rectangle. solid: Callable(Vector2) -> bool, true where a
## wall or piece of furniture stands.
func _init(area: Rect2, solid: Callable, seed_value: int) -> void:
	level = area
	columns = maxi(ceili(area.size.x / STEP), 1)
	rows = maxi(ceili(area.size.y / STEP), 1)
	_solid = solid
	_salt = seed_value
	_noise.seed = seed_value
	_noise.frequency = 0.09


func cell_of(point: Vector2) -> Vector2i:
	var local := (point - level.position) / STEP
	return Vector2i(floori(local.x), floori(local.y))


func center_of(cell: Vector2i) -> Vector2:
	return level.position + (Vector2(cell) + Vector2.ONE * 0.5) * STEP


func in_level(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < columns and cell.y < rows


## True when mass may not lie here: outside the level, near its edge or on something solid.
func blocked(point: Vector2) -> bool:
	if not level.grow(-EDGE_MARGIN).has_point(point):
		return true
	return _is_solid(cell_of(point))


## True when something solid (not just the level edge) stands at the point.
func solid_at(point: Vector2) -> bool:
	return _is_solid(cell_of(point))


func _is_solid(cell: Vector2i) -> bool:
	if not in_level(cell):
		return true
	if not _cache.has(cell):
		_cache[cell] = _solid.is_valid() and bool(_solid.call(center_of(cell)))
	return _cache[cell]


## The free cell centre nearest to point (spiral search), or the point when none is near.
func nearest_free(point: Vector2, reach: float = 3.0) -> Vector2:
	var home := cell_of(point)
	if not _is_solid(home) and level.grow(-EDGE_MARGIN).has_point(point):
		return point
	for ring in range(1, ceili(reach / STEP) + 1):
		var best := Vector2.INF
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var candidate := center_of(home + Vector2i(dx, dz))
				if not blocked(candidate) and (best == Vector2.INF or candidate.distance_to(point) < best.distance_to(point)):
					best = candidate
		if best != Vector2.INF:
			return best
	return point


## A winding curve from one point to another. Always returns at least the two
## end points; solid cells are crossed only when nothing else connects them.
func route(from: Vector2, to: Vector2, wander: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var direct := from.distance_to(to)
	var cells := _search(from, to, wander, true)
	if cells.is_empty():
		cells = _search(from, to, wander, false)
	var curve := _smooth(from, to, cells, rng)
	if direct > 3.0 and _length(curve) < direct * MIN_WIND:
		# Too straight: bend it through a point to one side of the middle.
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var normal := (to - from).orthogonal().normalized() * side
		var middle := nearest_free((from + to) * 0.5 + normal * direct * rng.randf_range(0.18, 0.3), 4.0)
		var first := _smooth(from, middle, _search(from, middle, wander, true), rng)
		var second := _smooth(middle, to, _search(middle, to, wander, true), rng)
		first.append_array(second.slice(1))
		curve = first
	return curve


func _length(curve: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, curve.size()):
		total += curve[index - 1].distance_to(curve[index])
	return total


# Cell centres of the cheapest route, or [] when the window holds none.
func _search(from: Vector2, to: Vector2, wander: float, windowed: bool) -> Array[Vector2i]:
	var start := cell_of(from)
	var goal := cell_of(to)
	var low := Vector2i(0, 0)
	var high := Vector2i(columns - 1, rows - 1)
	if windowed:
		var margin := ceili(maxf(WINDOW_MARGIN, from.distance_to(to) * 0.7) / STEP)
		low = Vector2i(maxi(mini(start.x, goal.x) - margin, 0), maxi(mini(start.y, goal.y) - margin, 0))
		high = Vector2i(mini(maxi(start.x, goal.x) + margin, columns - 1), mini(maxi(start.y, goal.y) + margin, rows - 1))
	if not in_level(start) or not in_level(goal):
		return []
	var open := _Heap.new()
	var cost := {start: 0.0}
	var came := {}
	open.push(0.0, start)
	while not open.is_empty():
		var current: Vector2i = open.pop()
		if current == goal:
			return _unwind(came, goal)
		for step in NEIGHBOURS:
			var next := current + step
			if next.x < low.x or next.y < low.y or next.x > high.x or next.y > high.y:
				continue
			var price := _price(next, step, wander, next == goal)
			var total: float = cost[current] + price
			if total < float(cost.get(next, INF)):
				cost[next] = total
				came[next] = current
				open.push(total + _heuristic(next, goal), next)
	return []


func _heuristic(cell: Vector2i, goal: Vector2i) -> float:
	var dx := absf(cell.x - goal.x)
	var dz := absf(cell.y - goal.y)
	return (maxf(dx, dz) + 0.41421356 * minf(dx, dz)) * STEP


# Length of the step times how unwelcome the cell is: solid cells are costly,
# the rest wander with a slow noise field plus a hash jitter.
func _price(cell: Vector2i, step: Vector2i, wander: float, is_goal: bool) -> float:
	var length := (1.41421356 if step.x != 0 and step.y != 0 else 1.0) * STEP
	var unwelcome := 0.0
	if _is_solid(cell) and not is_goal:
		unwelcome = SOLID_COST
	var field := _noise.get_noise_2d(cell.x, cell.y) * 0.5 + 0.5
	var jitter := float(absi(hash(Vector3i(cell.x, cell.y, _salt))) % 1000) / 1000.0
	return length * (1.0 + unwelcome + wander * (field * 2.2 + jitter * 0.6))


func _unwind(came: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [goal]
	var current := goal
	while came.has(current):
		current = came[current]
		cells.push_front(current)
	return cells


# Chaikin-smoothed curve through the cells, ending exactly on the two points.
func _smooth(from: Vector2, to: Vector2, cells: Array[Vector2i], rng: RandomNumberGenerator) -> PackedVector2Array:
	var points := PackedVector2Array([from])
	var stride := 3
	for index in range(stride, cells.size() - 1, stride):
		points.append(center_of(cells[index]) + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)))
	points.append(to)
	for _pass in 2:
		var refined := PackedVector2Array([points[0]])
		for index in range(points.size() - 1):
			refined.append(points[index].lerp(points[index + 1], 0.25))
			refined.append(points[index].lerp(points[index + 1], 0.75))
		refined.append(points[points.size() - 1])
		points = refined
	return points


## Binary min-heap of cells by priority.
class _Heap:
	var _keys: Array[float] = []
	var _items: Array[Vector2i] = []

	func is_empty() -> bool:
		return _items.is_empty()

	func push(key: float, item: Vector2i) -> void:
		_keys.append(key)
		_items.append(item)
		var child := _items.size() - 1
		while child > 0:
			@warning_ignore("integer_division")
			var parent := (child - 1) / 2
			if _keys[parent] <= _keys[child]:
				break
			_swap(parent, child)
			child = parent

	func pop() -> Vector2i:
		var top := _items[0]
		var last := _items.size() - 1
		_swap(0, last)
		_keys.remove_at(last)
		_items.remove_at(last)
		var parent := 0
		while true:
			var left := parent * 2 + 1
			var smallest := parent
			if left < _items.size() and _keys[left] < _keys[smallest]:
				smallest = left
			if left + 1 < _items.size() and _keys[left + 1] < _keys[smallest]:
				smallest = left + 1
			if smallest == parent:
				break
			_swap(parent, smallest)
			parent = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var key := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = key
		var item := _items[a]
		_items[a] = _items[b]
		_items[b] = item
