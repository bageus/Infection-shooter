extends RefCounted
## Auto-placement of light switches, fire alarm sounders and call points on walls
## and columns. Works on a WallFixtureGeometry and returns planner layout records.

const SWITCH := "res://models/objects/enviroments/13/13_wall_light_switch.glb"
const ALARM := "res://models/objects/enviroments/13/13_wall_emergency_alarm.glb"
const CALL_POINT := "res://models/objects/enviroments/13/13_wall_fire_call_point.glb"
# Distance from the model origin back to its mounting plane (model bounds).
const EXTINGUISHER := "res://models/objects/enviroments/09/09_fire_extinguisher.glb"
# Wall-mounted objects stand 5 mm off the wall (PlanningSurfacePlacement.WALL_CLEARANCE).
const GAP := 0.005
const BACK := {SWITCH: 0.012, ALARM: 0.055, CALL_POINT: 0.045, EXTINGUISHER: 0.032}
const EXTINGUISHER_HEIGHT := 1.5
const EXTINGUISHER_BANDS := [Vector2(1.45, 2.15)]
# The extinguisher model faces local -X, so it is turned a quarter turn from the wall normal.
const EXTINGUISHER_TURN := 90.0
const SWITCH_HEIGHT := 1.25
const ALARM_HEIGHT := 2.5
const CALL_POINT_HEIGHT := 1.5
const SWITCH_BANDS := [Vector2(1.10, 1.40)]
const ALARM_BANDS := [Vector2(2.35, 2.65), Vector2(1.35, 1.65)]
const SWITCHES_PER_DOOR := 3
const ALARMS_PER_DOOR := 1
const PITCH := 0.09
const HALF_SWITCH := 0.043
const SPREAD_STEP := 0.5

var geometry: RefCounted
# Which automatic groups the planner asked for: light switches, fire alarms with call points.
var enabled := {"switches": true, "fire": true}
var records: Array = []
var shortfall := {"switch": 0, "alarm": 0}
var _switches: Dictionary = {} # level -> Array[Vector2]


func _init(model: RefCounted, groups: Dictionary = {}) -> void:
	geometry = model
	enabled = {"switches": bool(groups.get("switches", true)), "fire": bool(groups.get("fire", true))}


func run() -> Array:
	for level in geometry.levels():
		var doors := _doors_of(level)
		_extinguishers(level)
		var glass := _glass_count(level)
		if enabled.switches:
			var hand: Array[Dictionary] = geometry.manual_of("switch", level)
			_switches[level] = hand.map(func(item: Dictionary) -> Vector2: return item.at)
			var left := 0
			for index in doors.size():
				left += _switches_for_door(doors[index], index, _take_manual(doors[index], hand))
			_spread_switches(level, maxi(0, left + glass * SWITCHES_PER_DOOR - hand.size()))
		if enabled.fire:
			var alarms: Array[Dictionary] = geometry.manual_of("alarm", level)
			_spread_alarms(level, maxi(0, (doors.size() + glass) * ALARMS_PER_DOOR - alarms.size()), alarms)
	return records


## One extinguisher per column at 1.5 m, on its first free face; a column that
## already has one is left alone.
func _extinguishers(level: int) -> void:
	for piece: Dictionary in geometry.pieces:
		if piece.level != level or not piece.box or geometry.column_has_extinguisher(piece):
			continue
		for face: Dictionary in geometry.faces_of_level(level):
			if face.piece == piece.id and geometry.clear_spot(face, 0.0, 0.12, EXTINGUISHER_BANDS):
				var point: Vector2 = geometry.face_point(face, 0.0) + face.n * (float(BACK[EXTINGUISHER]) + GAP)
				records.append({"scene": EXTINGUISHER, "x": point.x, "y": face.base + EXTINGUISHER_HEIGHT, "z": point.y,
					"rotation_y": rad_to_deg(atan2(face.n.x, face.n.y)) + EXTINGUISHER_TURN, "scale_x": 1.0, "scale_y": 1.0, "scale_z": 1.0,
					"auto_fixture": "extinguisher"})
				geometry.add_blocker(AABB(Vector3(point.x - 0.15, face.base + 1.45, point.y - 0.15), Vector3(0.3, 0.7, 0.3)))
				break


func _glass_count(level: int) -> int:
	return geometry.glass_doors.filter(func(door: Dictionary) -> bool: return door.level == level).size()


func _doors_of(level: int) -> Array:
	var out: Array = []
	for door: Dictionary in geometry.doors:
		if door.level == level:
			out.append(door)
	out.sort_custom(func(a, b): return a.pivot.x < b.pivot.x or (a.pivot.x == b.pivot.x and a.pivot.y < b.pivot.y))
	return out


## Hand-placed switches beside the door (either side; the key side only for a fire door)
## count toward its three; they are removed from `hand` so no other door counts them too.
func _take_manual(door: Dictionary, hand: Array[Dictionary]) -> int:
	var taken := 0
	for item in hand.duplicate():
		if taken >= SWITCHES_PER_DOOR:
			break
		var local: Vector2 = item.at - door.c
		var side := signf(local.dot(door.n))
		if absf(absf(local.dot(door.n)) - door.half.y) > 0.2 or absf(local.dot(door.t)) > 3.2 or (door.fire and side > 0.0):
			continue
		hand.erase(item)
		taken += 1
	return taken


## Places the three points of one door; returns how many could not be placed.
func _switches_for_door(door: Dictionary, index: int, credit: int = 0) -> int:
	var sides: Array = [-1.0] if door.fire else ([1.0, -1.0] if index % 2 == 0 else [-1.0, 1.0])
	var wanted := [SWITCHES_PER_DOOR] if door.fire else [2, 1]
	for slot in range(wanted.size() - 1, -1, -1):
		var used := mini(credit, wanted[slot])
		wanted[slot] -= used
		credit -= used
	var missing := 0
	for slot in wanted.size():
		var order: Array = [sides[slot]] if door.fire else [sides[slot], sides[1 - slot]]
		var need: int = wanted[slot]
		while need > 0:
			var placed := 0
			for size in range(need, 0, -1):
				placed = size if _place_gang(door, order, size) else 0
				if placed > 0:
					break
			if placed == 0:
				missing += need
				break
			need -= placed
	return missing


func _place_gang(door: Dictionary, sides: Array, size: int) -> bool:
	var half_width := HALF_SWITCH + (size - 1) * PITCH * 0.5
	for side in sides:
		var best := {}
		var best_distance := INF
		for face: Dictionary in geometry.faces_of_level(door.level):
			if face.column or face.n.dot(door.n * side) < 0.98 or absf((face.o - door.c).dot(door.n * side) - door.half.y) > 0.12:
				continue
			for along in _positions(face, half_width, 0.05):
				var distance := snappedf(absf((geometry.face_point(face, along) - door.c).dot(door.t)), 0.002)
				if distance < best_distance and distance < 3.2 and geometry.clear_spot(face, along, half_width, SWITCH_BANDS):
					best_distance = distance
					best = {"face": face, "along": along}
		if not best.is_empty():
			_put_gang(best.face, best.along, size, door.level)
			return true
	return false


func _positions(face: Dictionary, half_width: float, step: float) -> Array[float]:
	var out: Array[float] = []
	for span: Vector2 in face.ranges:
		var along: float = span.x + geometry.END_MARGIN + half_width
		while along <= span.y - geometry.END_MARGIN - half_width + 0.0001:
			out.append(along)
			along += step
	return out


func _put_gang(face: Dictionary, along: float, size: int, level: int) -> void:
	for member in size:
		var shifted := along + (member - (size - 1) * 0.5) * PITCH
		_put(SWITCH, face, shifted, SWITCH_HEIGHT, "switch")
		_switches[level].append(geometry.face_point(face, shifted))


func _put(path: String, face: Dictionary, along: float, height: float, kind: String) -> void:
	var point: Vector2 = geometry.face_point(face, along) + face.n * (float(BACK[path]) + GAP)
	records.append({"scene": path, "x": point.x, "y": face.base + height, "z": point.y,
		"rotation_y": rad_to_deg(atan2(face.n.x, face.n.y)), "scale_x": 1.0, "scale_y": 1.0, "scale_z": 1.0,
		"auto_fixture": kind})
	var box := AABB(Vector3(point.x - 0.07, face.base + height - 0.07, point.y - 0.07), Vector3(0.14, 0.14, 0.14))
	geometry.add_blocker(box)


func _spread_switches(level: int, count: int) -> void:
	var picks := _spread(level, count, HALF_SWITCH, SWITCH_BANDS, _switches[level], false)
	for pick: Dictionary in picks:
		_put(SWITCH, pick.face, pick.along, SWITCH_HEIGHT, "switch")
	shortfall.switch += count - picks.size()


func _spread_alarms(level: int, count: int, hand: Array[Dictionary]) -> void:
	var seeds: Array = hand.map(func(item: Dictionary) -> Vector2: return item.at)
	var picks := _spread(level, count, 0.08, ALARM_BANDS, seeds, true)
	for pick: Dictionary in picks:
		_put(ALARM, pick.face, pick.along, ALARM_HEIGHT, "alarm")
		_put(CALL_POINT, pick.face, pick.along, CALL_POINT_HEIGHT, "call_point")
	shortfall.alarm += count - picks.size()


## Farthest-point sampling over every free wall spot of the level, so the points
## spread out instead of clustering.
func _spread(level: int, count: int, half_width: float, bands: Array, seeds: Array, columns: bool) -> Array:
	var candidates: Array[Dictionary] = []
	for face: Dictionary in geometry.faces_of_level(level):
		if face.column and not columns:
			continue
		for along in _positions(face, half_width, SPREAD_STEP):
			if geometry.clear_spot(face, along, half_width, bands):
				candidates.append({"face": face, "along": along, "at": geometry.face_point(face, along)})
	var nearest: Array[float] = []
	for candidate in candidates:
		var distance := INF
		for anchor: Vector2 in seeds:
			distance = snappedf(minf(distance, candidate.at.distance_to(anchor)), 0.002)
		nearest.append(distance)
	var picks: Array = []
	while picks.size() < count and not candidates.is_empty():
		var best := 0
		for index in candidates.size():
			if nearest[index] > nearest[best]:
				best = index
		var pick: Dictionary = candidates[best]
		candidates.remove_at(best)
		nearest.remove_at(best)
		if not geometry.clear_spot(pick.face, pick.along, half_width, bands):
			continue
		picks.append(pick)
		geometry.add_blocker(AABB(Vector3(pick.at.x - 0.07, pick.face.base + bands[0].x, pick.at.y - 0.07), Vector3(0.14, bands[0].y - bands[0].x, 0.14)))
		for index in candidates.size():
			nearest[index] = snappedf(minf(nearest[index], candidates[index].at.distance_to(pick.at)), 0.002)
	return picks
