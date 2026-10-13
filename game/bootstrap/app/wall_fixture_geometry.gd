extends RefCounted
## Flat model of a saved layout for wall fixtures: solid wall pieces, the faces
## that can carry a fixture, and what stands in front of them. Positions are 2D
## (x, z); heights are measured from the floor of the piece's own level.

const STRUCTURAL := "res://game/presentation/office_floor/public/structural/"
# Nothing is mounted closer to a door's centre than the outer edge of its casing
# (the trim spans 0.75..0.85 m either side, measured on the door models).
const OPENING := 0.85
const END_MARGIN := 0.04
const CLEAR_DEPTH := 0.5
const CELL := 2.0
const LEVEL_HEIGHT := 3.0
# Fixtures placed by hand that count toward the per-door totals.
const MANUAL := {"13_wall_light_switch.glb": "switch", "13_wall_emergency_alarm.glb": "alarm"}
# Pieces that carry fixtures. half = (half length, half thickness) in piece axes.
const SOLID := {
	"wall_straight": {"half": Vector2(1.0, 0.095)},
	"wall_door": {"half": Vector2(1.0, 0.1375), "door": true},
	"wall_door_2_without": {"half": Vector2(1.0, 0.1375), "door": true},
	"wall_door_3": {"half": Vector2(1.0, 0.1375), "door": true},
	"wall_door_3_without": {"half": Vector2(1.0, 0.1375), "door": true},
	"wall_emergency_door": {"half": Vector2(1.0, 0.1375), "door": true, "fire": true},
	"column": {"half": Vector2(0.6, 0.6), "box": true, "face": 0.512}, # body, inside its plinth and cap
	"column_2": {"half": Vector2(0.6, 0.6), "box": true}
}
# Pieces that only block the space in front of a wall (glass, windows, elevator).
const OTHER := {
	"window_double": {"half": Vector2(1.0, 0.095)},
	"glass_wall_full": {"half": Vector2(1.0, 0.055)},
	"glass_partition_blinds": {"half": Vector2(1.0, 0.06)},
	"glass_partition_half": {"half": Vector2(1.0, 0.06)},
	"wall_half_panel": {"half": Vector2(1.0, 0.096)},
	"sliding_glass_door": {"half": Vector2(1.0, 0.07), "shift": -2.0, "glass_door": true},
	"elevator_door": {"half": Vector2(2.0, 0.17)}
}

var pieces: Array[Dictionary] = []
var faces: Array[Dictionary] = []
var doors: Array[Dictionary] = []
var glass_doors: Array[Dictionary] = [] # count toward the totals but carry no fixtures of their own
var blockers: Array[AABB] = []
var extinguishers: Array[Vector3] = [] # (x, height, z) of every extinguisher already in the layout
var manual: Array[Dictionary] = [] # switches and alarms placed by hand: {kind, at, y}
var _piece_grid := {}
var _blocker_grid := {}
var _all_pieces: Array[Dictionary] = []


static func level_of(base: float) -> int:
	return int(roundf(base / LEVEL_HEIGHT))


static func axes(yaw_degrees: float) -> Array[Vector2]:
	var yaw := deg_to_rad(yaw_degrees)
	return [Vector2(cos(yaw), -sin(yaw)), Vector2(sin(yaw), cos(yaw))]


## records: dictionaries with scene, x, y, z and rotation_y.
func load_records(records: Array) -> void:
	for record: Dictionary in records:
		var scene := str(record.get("scene", ""))
		if scene.get_file() == "09_fire_extinguisher.glb" and not bool(record.get("auto", false)):
			extinguishers.append(Vector3(float(record.get("x", 0.0)), float(record.get("y", 0.0)), float(record.get("z", 0.0))))
		var kind: String = MANUAL.get(scene.get_file(), "")
		if not kind.is_empty() and str(record.get("auto_fixture", "")).is_empty():
			manual.append({"kind": kind, "at": Vector2(float(record.get("x", 0.0)), float(record.get("z", 0.0))), "y": float(record.get("y", 0.0))})
		if not scene.begins_with(STRUCTURAL):
			continue
		var file := scene.get_file().get_basename()
		var spec: Dictionary = SOLID.get(file, OTHER.get(file, {}))
		if spec.is_empty():
			continue
		_add_piece(record, file, spec)
	for piece in pieces:
		_add_faces(piece)
		if piece.door:
			doors.append(piece)


func _add_piece(record: Dictionary, file: String, spec: Dictionary) -> void:
	var frame := axes(float(record.get("rotation_y", 0.0)))
	var base := snappedf(float(record.get("y", 0.0)), 0.1)
	var centre := Vector2(float(record.get("x", 0.0)), float(record.get("z", 0.0))) + frame[0] * float(spec.get("shift", 0.0))
	var half: Vector2 = spec.half
	var piece := {"id": _all_pieces.size(), "c": centre, "t": frame[0], "n": frame[1], "half": half, "base": base,
		"level": level_of(base), "door": bool(spec.get("door", false)), "fire": bool(spec.get("fire", false)),
		"box": bool(spec.get("box", false)), "face": float(spec.get("face", 0.0)), "mount": SOLID.has(file), "file": file,
		"pivot": Vector2(float(record.get("x", 0.0)), float(record.get("z", 0.0)))}
	_all_pieces.append(piece)
	if spec.get("glass_door", false):
		glass_doors.append(piece)
	var reach := half.x + half.y + 0.7
	_index(_piece_grid, centre, reach, piece)
	if piece.mount:
		pieces.append(piece)


func _add_faces(piece: Dictionary) -> void:
	var half: Vector2 = piece.half
	var face_half: Vector2 = Vector2(piece.face, piece.face) if piece.face > 0.0 else half
	var main := [Vector2(-half.x, -OPENING), Vector2(OPENING, half.x)] if piece.door else [Vector2(-face_half.x, face_half.x)]
	for side in [1.0, -1.0]:
		_add_face(piece, piece.c + piece.n * side * face_half.y, piece.n * side, piece.t, main)
		if piece.box:
			_add_face(piece, piece.c + piece.t * side * face_half.x, piece.t * side, piece.n, [Vector2(-face_half.y, face_half.y)])


func _add_face(piece: Dictionary, origin: Vector2, normal: Vector2, tangent: Vector2, ranges: Array) -> void:
	faces.append({"piece": piece.id, "o": origin, "n": normal, "t": tangent, "ranges": ranges,
		"base": piece.base, "level": piece.level, "door": piece.door, "column": piece.box})


func add_blocker(box: AABB) -> void:
	blockers.append(box)
	var centre := Vector2(box.get_center().x, box.get_center().z)
	_index(_blocker_grid, centre, maxf(box.size.x, box.size.z) * 0.5 + 0.7, box)


func _index(grid: Dictionary, centre: Vector2, reach: float, item: Variant) -> void:
	var low := Vector2i(floori((centre.x - reach) / CELL), floori((centre.y - reach) / CELL))
	var high := Vector2i(floori((centre.x + reach) / CELL), floori((centre.y + reach) / CELL))
	for gx in range(low.x, high.x + 1):
		for gz in range(low.y, high.y + 1):
			var key := Vector2i(gx, gz)
			if not grid.has(key):
				grid[key] = []
			grid[key].append(item)


func _near(grid: Dictionary, point: Vector2) -> Array:
	return grid.get(Vector2i(floori(point.x / CELL), floori(point.y / CELL)), [])


## Floor height of the level a thing at (point, height) belongs to: the nearest piece
## whose storey contains it, or the 3 m storey grid (signs hang about 1.75 m up) when no piece is close.
func floor_at(point: Vector2, height: float) -> float:
	var best := INF
	var base := NAN
	for piece: Dictionary in _near(_piece_grid, point):
		if height < piece.base - 0.3 or height > piece.base + LEVEL_HEIGHT + 0.3:
			continue
		var distance := _distance_to_piece(piece, point)
		if distance < best:
			best = distance
			base = piece.base
	return base if is_finite(base) and best <= 1.0 else snappedf(roundf((height - 1.75) / LEVEL_HEIGHT) * LEVEL_HEIGHT, 0.1)


func _distance_to_piece(piece: Dictionary, point: Vector2) -> float:
	var local: Vector2 = point - piece.c
	var along: float = absf(local.dot(piece.t)) - piece.half.x
	var across: float = absf(local.dot(piece.n)) - piece.half.y
	return Vector2(maxf(along, 0.0), maxf(across, 0.0)).length()


## True when an extinguisher already hangs on (or right beside) the column.
func column_has_extinguisher(column: Dictionary) -> bool:
	for spot in extinguishers:
		var local: Vector2 = Vector2(spot.x, spot.z) - column.c
		if absf(local.dot(column.t)) <= column.half.x + 0.5 and absf(local.dot(column.n)) <= column.half.y + 0.5 and spot.y > column.base + 0.6 and spot.y < column.base + 2.4:
			return true
	return false


## Hand-placed fixtures of a kind on a level; their level comes from the walls around them.
func manual_of(kind: String, level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in manual:
		if item.kind == kind and level_of(floor_at(item.at, item.y)) == level:
			out.append(item)
	return out


func faces_of_level(level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for face in faces:
		if face.level == level:
			out.append(face)
	return out


func levels() -> Array[int]:
	var out: Array[int] = []
	for piece in pieces + glass_doors:
		if not out.has(piece.level):
			out.append(piece.level)
	out.sort()
	return out


func face_point(face: Dictionary, along: float) -> Vector2:
	return face.o + face.t * along


## True when a fixture of half width half_width fits on the face at `along`, the
## half metre in front of it is empty, and nothing stands in the height bands.
func clear_spot(face: Dictionary, along: float, half_width: float, bands: Array) -> bool:
	if not _within_range(face, along, half_width):
		return false
	var point := face_point(face, along)
	var walls := _rect(point + face.n * (0.05 + CLEAR_DEPTH) * 0.5, face.t, Vector2(half_width + 0.06, (CLEAR_DEPTH - 0.05) * 0.5))
	for piece: Dictionary in _near(_piece_grid, point):
		if piece.id != face.piece and absf(piece.base - face.base) < 1.5 and _overlap(walls, _rect(piece.c, piece.t, piece.half)):
			return false
	var front := _rect(point + face.n * CLEAR_DEPTH * 0.5, face.t, Vector2(half_width + 0.06, CLEAR_DEPTH * 0.5))
	for box: AABB in _near(_blocker_grid, point):
		if _in_bands(box, face.base, bands) and _overlap(front, _rect(Vector2(box.get_center().x, box.get_center().z), Vector2(1, 0), Vector2(box.size.x, box.size.z) * 0.5)):
			return false
	return true


func _within_range(face: Dictionary, along: float, half_width: float) -> bool:
	for span: Vector2 in face.ranges:
		if along - half_width >= span.x + END_MARGIN and along + half_width <= span.y - END_MARGIN:
			return true
	return false


static func _in_bands(box: AABB, base: float, bands: Array) -> bool:
	for band: Vector2 in bands:
		if box.position.y < base + band.y and box.end.y > base + band.x:
			return true
	return false


static func _rect(centre: Vector2, tangent: Vector2, half: Vector2) -> Dictionary:
	return {"c": centre, "t": tangent, "h": half}


static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var a_normal: Vector2 = Vector2(a.t.y, -a.t.x)
	var b_normal: Vector2 = Vector2(b.t.y, -b.t.x)
	var gap: Vector2 = b.c - a.c
	for axis: Vector2 in [a.t, a_normal, b.t, b_normal]:
		var reach_a: float = absf(a.t.dot(axis)) * a.h.x + absf(a_normal.dot(axis)) * a.h.y
		var reach_b: float = absf(b.t.dot(axis)) * b.h.x + absf(b_normal.dot(axis)) * b.h.y
		if absf(gap.dot(axis)) > reach_a + reach_b:
			return false
	return true
