extends SceneTree
## ADR-0062: the planner's procedural biomass joins every spawn hole with a
## winding vein, rings a lone hole, keeps off solid cells and the level edge,
## and is repeatable for one seed.

const GENERATOR := preload("res://game/bootstrap/app/biomass_generator.gd")
const LEVEL := Rect2(-20.0, -15.0, 40.0, 30.0)

var failures := 0


func _init() -> void:
	_check_joined()
	_check_lone_hole()
	_check_constraints()
	_check_amount()
	print("biomass generator tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


# A wall across the middle with a doorway at the north end.
func _wall(point: Vector2) -> bool:
	return absf(point.x) < 0.3 and point.y > -10.0 and point.y < 8.0


func _positions(pieces: Array[Dictionary]) -> PackedVector2Array:
	var points := PackedVector2Array()
	for piece in pieces:
		points.append(piece["position"])
	return points


# Pieces that follow one another within `gap` metres form one mass.
func _connected(points: PackedVector2Array, from: Vector2, to: Vector2, gap: float) -> bool:
	var seen := {}
	var queue: Array[int] = []
	for index in points.size():
		if points[index].distance_to(from) <= 2.5:
			queue.append(index)
			seen[index] = true
	while not queue.is_empty():
		var current: int = queue.pop_back()
		if points[current].distance_to(to) <= 2.5:
			return true
		for index in points.size():
			if not seen.has(index) and points[index].distance_to(points[current]) <= gap:
				seen[index] = true
				queue.append(index)
	return false


func _check_joined() -> void:
	var holes := [Vector2(-12.0, 0.0), Vector2(12.0, 0.0), Vector2(-4.0, 11.0)]
	var pieces := GENERATOR.plan(LEVEL, holes, _wall, 0.5, 7)
	var points := _positions(pieces)
	_expect(pieces.size() > 40, "Three holes get a mass of pieces (%d)." % pieces.size())
	for pair in [[0, 1], [0, 2], [1, 2]]:
		_expect(_connected(points, holes[pair[0]], holes[pair[1]], 1.3), "Holes %d and %d are joined by an unbroken mass." % [pair[0], pair[1]])
	for hole: Vector2 in holes:
		var near := 0
		for point in points:
			near += 1 if point.distance_to(hole) < 2.5 else 0
		_expect(near >= 3, "Mass gathers round the hole at %s (%d pieces)." % [hole, near])
	# The two far holes are 24 m apart across the wall: the vein must wind round it.
	var tree := _positions(GENERATOR.plan(LEVEL, [Vector2(-12.0, 0.0), Vector2(12.0, 0.0)], _wall, 0.5, 3))
	var crossing := 0
	for point in tree:
		crossing += 1 if absf(point.x) < 1.5 else 0
	_expect(crossing > 0, "The vein crosses the wall line, and only through the doorway (%d pieces)." % crossing)


func _check_lone_hole() -> void:
	var hole := Vector2(3.0, -2.0)
	var points := _positions(GENERATOR.plan(LEVEL, [hole], _wall, 0.5, 11))
	var quadrants := {}
	for point in points:
		var offset := point - hole
		if offset.length() < 4.0:
			quadrants[Vector2i(signi(int(offset.x)), signi(int(offset.y)))] = true
	_expect(points.size() > 15, "A lone hole is ringed by mass (%d pieces)." % points.size())
	_expect(quadrants.size() >= 4, "The mass round a lone hole reaches several sides (%d)." % quadrants.size())


func _check_constraints() -> void:
	var holes := [Vector2(-12.0, 0.0), Vector2(12.0, 0.0), Vector2(-18.5, -13.5)]
	var pieces := GENERATOR.plan(LEVEL, holes, _wall, 1.0, 5)
	var bad_solid := 0
	var bad_edge := 0
	for piece in pieces:
		var at: Vector2 = piece["position"]
		bad_solid += 1 if _wall(at) else 0
		bad_edge += 0 if LEVEL.grow(-0.2).has_point(at) else 1
		_expect(str(piece["texture"]).begins_with("biomass_") and float(piece["scale"]) > 0.2, "A planned piece is a sized biomass id.") if bad_solid + bad_edge == 1 else null
	_expect(bad_solid == 0, "No piece stands on a wall.")
	_expect(bad_edge == 0, "No piece leaves the level, even with a hole at its corner.")
	_expect(pieces.size() <= GENERATOR.MAX_PIECES, "The plan stays within the piece budget (%d)." % pieces.size())
	var again := GENERATOR.plan(LEVEL, holes, _wall, 1.0, 5)
	_expect(again.size() == pieces.size() and (again[0]["position"] as Vector2).is_equal_approx(pieces[0]["position"]), "One seed gives one plan.")
	var other := GENERATOR.plan(LEVEL, holes, _wall, 1.0, 6)
	_expect(other.size() != pieces.size() or not (other[0]["position"] as Vector2).is_equal_approx(pieces[0]["position"]), "Another seed gives another plan.")
	_expect(GENERATOR.plan(LEVEL, [], _wall, 1.0, 1).is_empty(), "Without holes nothing is planned.")
	_expect(GENERATOR.plan(LEVEL, holes, _wall, 0.0, 1).is_empty(), "With no amount nothing is planned.")


func _check_amount() -> void:
	var holes := [Vector2(-12.0, 0.0), Vector2(12.0, 0.0)]
	var little := _area(GENERATOR.plan(LEVEL, holes, _wall, 0.1, 9))
	var much := _area(GENERATOR.plan(LEVEL, holes, _wall, 0.9, 9))
	_expect(much > little * 1.5, "More amount covers more floor (%.0f against %.0f)." % [much, little])
	# A route over open floor winds: pieces stray from the straight line between the holes.
	var open := _positions(GENERATOR.plan(LEVEL, [Vector2(-15.0, -10.0), Vector2(15.0, -10.0)], func(_p: Vector2) -> bool: return false, 0.4, 2))
	var stray := 0.0
	for point in open:
		if point.x > -14.0 and point.x < 14.0:
			stray = maxf(stray, absf(point.y + 10.0))
	_expect(stray > 1.5, "The vein between two holes is not a straight line (strays %.1f m)." % stray)


# Floor the pieces cover, in square piece lengths.
func _area(pieces: Array[Dictionary]) -> float:
	var total := 0.0
	for piece in pieces:
		total += float(piece["scale"]) * float(piece["scale"])
	return total


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		print("FAIL: ", message)
