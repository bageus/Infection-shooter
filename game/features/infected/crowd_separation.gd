extends RefCounted
## Soft crowd spacing. Infected no longer collide with each other (a body-vs-body
## pair per neighbour made a 90-strong crowd the biggest physics cost); each one
## steers away from neighbours instead, read from a grid of last frame's positions.

## Most speed the spacing adds; each neighbour's share fades to zero one body width apart.
const PUSH_SPEED := 2.5
## Larger than the widest body pair (Colossus, about 1.3 m) so a 3x3 block of cells is enough.
const CELL := 2.0
const DEFAULT_RADIUS := 0.35
## Physics layer of living infected; saved maps stamp the old mask onto placed ones.
const INFECTED_LAYER := 2

static var _frame := -1
static var _current := {}
static var _previous := {}
static var _current_ids := {}
static var _previous_ids := {}
static var _current_positions := {}
static var _previous_positions := {}


static func body_radius(shape_node: CollisionShape3D, scale: float) -> float:
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		return (shape_node.shape as CapsuleShape3D).radius * scale
	return DEFAULT_RADIUS


## Registers `who` for this frame and returns the horizontal velocity that moves it
## out of its neighbours (zero when nobody is within two body radii).
static func spread(who: Node3D, shape_node: CollisionShape3D) -> Vector3:
	if who is CollisionObject3D:
		(who as CollisionObject3D).set_collision_mask_value(INFECTED_LAYER, false)
	var frame := Engine.get_physics_frames()
	if frame != _frame:
		_previous = _current if frame == _frame + 1 else {}
		_previous_ids = _current_ids if frame == _frame + 1 else {}
		_previous_positions = _current_positions if frame == _frame + 1 else {}
		_current_positions = {}
		_current = {}
		_current_ids = {}
		_frame = frame
	var self_id := who.get_instance_id()
	var position := who.global_position
	_current_positions[self_id] = position
	# Compare both bodies at the same frame; moving coincident pairs otherwise
	# see their shared velocity as separation and can remain exactly stacked.
	var previous_position: Vector3 = _previous_positions.get(self_id, position)
	var cell := Vector2i(floori(position.x / CELL), floori(position.z / CELL))
	# Packed arrays are values: append to a local copy and store it back.
	var registered: PackedVector3Array = _current.get(cell, PackedVector3Array())
	registered.append(position)
	_current[cell] = registered
	var registered_ids: PackedInt64Array = _current_ids.get(cell, PackedInt64Array())
	registered_ids.append(self_id)
	_current_ids[cell] = registered_ids
	var width := 2.0 * body_radius(shape_node, who.global_basis.x.length())
	var push := Vector3.ZERO
	var width_sq := width * width
	var previous_cell := Vector2i(floori(previous_position.x / CELL), floori(previous_position.z / CELL))
	for index in 9:
		var key := Vector2i(previous_cell.x + index % 3 - 1, previous_cell.y + floori(index / 3.0) - 1)
		var neighbours: Variant = _previous.get(key)
		if neighbours != null:
			var ids: PackedInt64Array = _previous_ids[key]
			var points: PackedVector3Array = neighbours
			for slot in points.size():
				if ids[slot] == self_id:
					continue
				var away := previous_position - points[slot]
				away.y = 0.0
				var length_sq := away.length_squared()
				if length_sq >= width_sq:
					continue
				if length_sq < 0.000001:
					# Exactly stacked: pick a stable direction so the pair can split.
					var angle := float(mini(self_id, ids[slot]) % 628) * 0.01
					away = Vector3(cos(angle), 0.0, sin(angle)) * 0.001
					if self_id > ids[slot]:
						away = -away
					length_sq = 0.000001
				var length := sqrt(length_sq)
				push += away / length * (1.0 - length / width)
	return push.limit_length(1.0) * PUSH_SPEED
