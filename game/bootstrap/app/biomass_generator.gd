extends RefCounted
## Procedural biomass for the planner (ADR-0062). Plans which biomass decals to
## lay on the floor of a level: every spawn hole is tied to the others by a
## winding vein (a minimum spanning tree plus a few loops), a lone hole is
## ringed by its own mass, and veins sprout side branches. Pieces overlap, so
## the fusion in presentation.office_floor builds varied structures from them.
## Pure planning: it returns piece descriptions and never touches the scene.

const PATHS := preload("res://game/bootstrap/app/biomass_paths.gd")
const VARIANTS := 6
## No plan holds more pieces than this, whatever the amount.
const MAX_PIECES := 450
## Piece spacing along a vein, in piece lengths.
const SPACING := 0.55
const WALK_STEP := 0.5
## How far from a vein mass looks for something to climb, and the probe step.
const HUG_REACH := 1.6
const HUG_STEP := 0.2

var _rng := RandomNumberGenerator.new()
var _paths: RefCounted
var _pieces: Array[Dictionary] = []
var _last_variant := 0
var _amount := 0.5


## level: world XZ rectangle. holes: Array[Vector2] of spawn holes on that floor.
## solid: Callable(Vector2) -> bool. amount: 0..1. Returns
## [{texture: "biomass_03", position: Vector2, yaw: float, scale: float}].
static func plan(level: Rect2, holes: Array, solid: Callable, amount: float, seed_value: int) -> Array[Dictionary]:
	var generator := new()
	return generator._run(level, holes, solid, clampf(amount, 0.0, 1.0), seed_value)


func _run(level: Rect2, holes: Array, solid: Callable, amount: float, seed_value: int) -> Array[Dictionary]:
	_rng.seed = seed_value
	_amount = amount
	_paths = PATHS.new(level, solid, seed_value)
	if holes.is_empty() or amount <= 0.0:
		return _pieces
	var spots: Array[Vector2] = []
	for hole: Vector2 in holes:
		spots.append(_paths.nearest_free(hole))
	var veins: Array[PackedVector2Array] = []
	for edge in _links(spots):
		veins.append(_paths.route(spots[edge.x], spots[edge.y], 0.8 + amount * 0.8, _rng))
	for vein in veins:
		_lay(vein, 1.0, 1.0)
	for spot in spots:
		_hub(spot, spots.size() == 1)
	for vein in veins:
		_sprout(vein, 1)
	for vein in veins:
		_hug(vein)
	return _pieces


# Index pairs to join: a minimum spanning tree over the holes, plus loops that
# grow with the amount.
func _links(spots: Array[Vector2]) -> Array[Vector2i]:
	var edges: Array[Vector2i] = []
	if spots.size() < 2:
		return edges
	var joined := [0]
	var rest := range(1, spots.size())
	while not rest.is_empty():
		var best := Vector2i(-1, -1)
		var best_length := INF
		for a: int in joined:
			for b: int in rest:
				var length := spots[a].distance_to(spots[b])
				if length < best_length:
					best_length = length
					best = Vector2i(a, b)
		edges.append(best)
		joined.append(best.y)
		rest.erase(best.y)
	var loops := int(round(maxf(_amount - 0.35, 0.0) * 1.6 * spots.size()))
	var spare: Array[Vector2i] = []
	for a in spots.size():
		for b in range(a + 1, spots.size()):
			if not edges.has(Vector2i(a, b)) and not edges.has(Vector2i(b, a)):
				spare.append(Vector2i(a, b))
	spare.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return spots[x.x].distance_to(spots[x.y]) < spots[y.x].distance_to(spots[y.y]))
	for index in mini(loops, spare.size()):
		edges.append(spare[index])
	return edges


# The mass round a hole: a heap of overlapping pieces and tendrils that run out
# of it. A lone hole has nothing else to join, so its mass is the larger.
func _hub(spot: Vector2, alone: bool) -> void:
	var boost := 1.5 if alone else 1.0
	var heap := 2 + int(_amount * 4.0 * boost)
	for _piece in heap:
		var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.2, 0.7 + _amount * 0.9 * boost)
		_drop(spot + offset, _rng.randf() * TAU, _base() * _rng.randf_range(0.9, 1.4))
	var tendrils := int((3.0 + _amount * 3.0) * boost)
	var turn := _rng.randf() * TAU
	for index in tendrils:
		var heading := turn + TAU * float(index) / tendrils + _rng.randf_range(-0.3, 0.3)
		var length := (2.0 + _amount * 3.5) * boost * _rng.randf_range(0.6, 1.2)
		_lay(_walk(spot, heading, length), 0.9, 0.3)


# Side branches off a vein; each may sprout a few of its own.
func _sprout(vein: PackedVector2Array, depth: int) -> void:
	if vein.size() < 4:
		return
	var count := int(_amount * 0.3 * _length(vein) / 3.0) + 1
	for _branch in count:
		var at := _rng.randi_range(1, vein.size() - 2)
		var tangent := (vein[at + 1] - vein[at - 1]).normalized()
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var heading := tangent.angle() + side * _rng.randf_range(0.7, 1.4)
		var branch := _walk(vein[at], heading, _rng.randf_range(1.5, 2.5 + _amount * 3.0))
		_lay(branch, 0.7, 0.25)
		if depth > 0 and _rng.randf() < _amount * 0.6:
			_sprout(branch, depth - 1)


# Mass that reaches a wall or a piece of furniture beside a vein and rides up
# its face: a larger piece stands on the floor right before the solid thing, and
# the floor fit folds whatever lies past its face up the surface.
func _hug(vein: PackedVector2Array) -> void:
	var attempts := int(_amount * 0.5 * _length(vein)) + 1
	for _attempt in attempts:
		var from := vein[_rng.randi_range(0, vein.size() - 1)]
		var heading := _rng.randf() * TAU
		var travelled := 0.0
		while travelled < HUG_REACH:
			var point := from + Vector2.from_angle(heading) * (travelled + HUG_STEP)
			if _paths.solid_at(point):
				var edge := from + Vector2.from_angle(heading) * travelled
				if not _paths.blocked(edge):
					var size := _base() * _rng.randf_range(1.2, 1.9)
					_drop(edge, heading + PI * 0.5 + _rng.randf_range(-0.4, 0.4), size)
				break
			travelled += HUG_STEP


func _length(curve: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, curve.size()):
		total += curve[index - 1].distance_to(curve[index])
	return total


# A curling walk from a point that stops at the first solid cell.
func _walk(from: Vector2, heading: float, length: float) -> PackedVector2Array:
	var curve := PackedVector2Array([from])
	var at := from
	var curl := _rng.randf_range(-0.35, 0.35)
	for _step in int(length / WALK_STEP):
		curl = clampf(curl + _rng.randf_range(-0.25, 0.25), -0.5, 0.5)
		heading += curl
		var next := at + Vector2.from_angle(heading) * WALK_STEP
		if _paths.blocked(next):
			break
		curve.append(next)
		at = next
	return curve


func _base() -> float:
	return lerpf(0.9, 1.7, _amount)


# Pieces along a curve; the width factor runs from `from` at its start to `to`
# at its end, so branches thin out. Some pieces get a smaller one on top.
func _lay(curve: PackedVector2Array, from: float, to: float) -> void:
	var total := _length(curve)
	if total < 0.05:
		return
	var travelled := 0.0
	var next_at := 0.0
	for index in range(1, curve.size()):
		var segment := curve[index] - curve[index - 1]
		var length := segment.length()
		if length < 0.0001:
			continue
		while next_at <= travelled + length:
			var along := (next_at - travelled) / length
			var width := lerpf(from, to, (travelled + length * along) / total)
			var size := _base() * width * _rng.randf_range(0.8, 1.2)
			var centre := curve[index - 1] + segment * along
			var normal := segment.orthogonal().normalized()
			_drop(centre + normal * _rng.randf_range(-0.2, 0.2) * size, segment.angle() + _rng.randf_range(-0.35, 0.35), size)
			if _rng.randf() < 0.35:
				var shift := normal * _rng.randf_range(0.15, 0.4) * size * (1.0 if _rng.randf() < 0.5 else -1.0)
				_drop(centre + shift, segment.angle() + _rng.randf_range(0.6, 1.4) * (1.0 if _rng.randf() < 0.5 else -1.0), size * _rng.randf_range(0.55, 0.85))
			next_at += SPACING * size
		travelled += length


# One piece, unless it would stand on something solid or past the level.
# `angle` is the direction of the piece's long axis on the XZ plane.
func _drop(at: Vector2, angle: float, size: float) -> void:
	if _pieces.size() >= MAX_PIECES or _paths.blocked(at):
		return
	var variant := _rng.randi_range(1, VARIANTS)
	if variant == _last_variant:
		variant = variant % VARIANTS + 1
	_last_variant = variant
	# A node turned by yaw t carries its long axis (-Z) to (-sin t, -cos t).
	var yaw := atan2(-cos(angle), -sin(angle))
	_pieces.append({"texture": "biomass_%02d" % variant, "position": at, "yaw": yaw, "scale": size})
