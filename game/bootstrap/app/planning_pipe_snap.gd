extends RefCounted
## Open ends of group 01 ducts and water pipes meet one to one; a piece raised to the ceiling
## turns its mounting side up and sits flush against it. Ends are in model coordinates.
const REACH := 0.45
const HEIGHT_TOLERANCE := 0.05
const CEILING_Y := 2.8 # wall height
const CEILING_REACH := 0.2
const CEILING_CLEARANCE := 0.002
const _DUCT_Y := 0.4
const _PIPE_FLOOR := 0.24
# basename: [kind, mounting side, [[end centre, outward normal], ...]]
const MODELS := {
	"01_duct_rect_straight": ["duct", Vector3.DOWN, [[Vector3(0, _DUCT_Y, -0.035), Vector3.FORWARD], [Vector3(0, _DUCT_Y, 2.035), Vector3.BACK]]],
	"01_duct_rect_elbow": ["duct", Vector3.DOWN, [[Vector3(0, _DUCT_Y, -0.035), Vector3.FORWARD], [Vector3(1.035, _DUCT_Y, 1.0), Vector3.RIGHT]]],
	"01_pipe_water_floor_straight": ["water", Vector3.DOWN, [[Vector3(0, _PIPE_FLOOR, -0.005), Vector3.FORWARD], [Vector3(0, _PIPE_FLOOR, 2.005), Vector3.BACK]]],
	"01_pipe_water_floor_elbow": ["water", Vector3.DOWN, [[Vector3(0, _PIPE_FLOOR, -0.005), Vector3.FORWARD], [Vector3(1.005, _PIPE_FLOOR, 1.0), Vector3.RIGHT]]],
	"01_pipe_water_wall_straight": ["water", Vector3.FORWARD, [[Vector3(0, -0.005, _PIPE_FLOOR), Vector3.DOWN], [Vector3(0, 2.005, _PIPE_FLOOR), Vector3.UP]]],
	"01_pipe_water_wall_elbow": ["water", Vector3.FORWARD, [[Vector3(0, -0.005, _PIPE_FLOOR), Vector3.DOWN], [Vector3(1.005, 1.0, _PIPE_FLOOR), Vector3.RIGHT]]],
}


static func _model(node: Node3D) -> Array:
	var path := str(node.get_meta("planning_scene_path", node.scene_file_path))
	if "model_path" in node:
		path = str(node.get("model_path"))
	return MODELS.get(path.get_file().get_basename().to_lower(), [])


## "duct" or "water" for a piece with known ends, "" for everything else.
static func kind_of(node: Node3D) -> String:
	var model := _model(node)
	return "" if model.is_empty() else str(model[0])


## World open ends {pos, normal} of the node placed at position.
static func world_ends(node: Node3D, position: Vector3) -> Array[Dictionary]:
	var ends: Array[Dictionary] = []
	var model := _model(node)
	if model.is_empty():
		return ends
	var frame := Transform3D(node.global_basis, position)
	for end: Array in model[2]:
		ends.append({"pos": frame * (end[0] as Vector3), "normal": (frame.basis * (end[1] as Vector3)).normalized()})
	return ends


## Position that joins the nearest same-kind open end facing this piece, or null.
## A wall piece moves only inside its wall plane, so its mounting side stays flush.
static func join(node: Node3D, position: Vector3, neighbors: Array[Dictionary], mounted: bool) -> Variant:
	var kind := kind_of(node)
	if kind.is_empty():
		return null
	var wall_normal: Vector3 = node.get_meta("planning_wall_normal", Vector3.ZERO)
	var mine := world_ends(node, position)
	var best: Variant = null
	var distance := REACH
	for record: Dictionary in neighbors:
		var other: Node3D = record["node"]
		if kind_of(other) != kind or bool(other.get_meta("planning_wall_mount", false)) != mounted:
			continue
		if mounted and (wall_normal == Vector3.ZERO or wall_normal.dot(other.get_meta("planning_wall_normal", Vector3.ZERO)) < 0.999):
			continue
		for a: Dictionary in mine:
			for b: Dictionary in world_ends(other, other.global_position):
				if (a.normal as Vector3).dot(b.normal) > -0.999:
					continue
				var shift: Vector3 = (b.pos as Vector3) - (a.pos as Vector3)
				if mounted:
					shift -= wall_normal * shift.dot(wall_normal)
				else:
					if absf(shift.y) > HEIGHT_TOLERANCE:
						continue
					shift.y = 0.0
				if shift.length() < distance:
					distance = shift.length()
					best = position + shift
	return best


static func _mount_world(node: Node3D) -> Vector3:
	return (node.global_basis * (_model(node)[1] as Vector3)).normalized()


## True when the mounting side faces up, i.e. the piece hangs from the ceiling.
static func on_ceiling(node: Node3D) -> bool:
	return kind_of(node) != "" and _mount_world(node).y > 0.99


## Raised free pieces flip mounting side up and sit under the ceiling; lowered ones flip back.
## Returns true while the piece hangs from the ceiling.
static func settle_ceiling(node: Node3D, bounds: AABB) -> bool:
	if kind_of(node).is_empty() or bool(node.get_meta("planning_wall_mount", false)):
		return false
	var box := node.global_transform * bounds
	var near := box.end.y >= CEILING_Y - CEILING_REACH
	var up := on_ceiling(node)
	var down := _mount_world(node).y < -0.99
	if up == near or (not up and not down):
		if up:
			node.global_position.y += CEILING_Y - CEILING_CLEARANCE - box.end.y
		return up
	var centre := box.get_center().y
	_flip(node)
	box = node.global_transform * bounds
	node.global_position.y += (CEILING_Y - CEILING_CLEARANCE - box.end.y) if near else (centre - box.get_center().y)
	return near


## Half turn about the horizontal axis that maps the two ends onto each other (or keeps a straight one).
static func _flip(node: Node3D) -> void:
	var ends := world_ends(node, node.global_position)
	var axis: Vector3 = ends[0].normal if (ends[0].normal as Vector3).dot(ends[1].normal) < -0.999 else (ends[0].normal as Vector3) + (ends[1].normal as Vector3)
	axis.y = 0.0
	if axis.length() < 0.001:
		return
	var turn := Basis(axis.normalized(), PI)
	var mid: Vector3 = ((ends[0].pos as Vector3) + (ends[1].pos as Vector3)) * 0.5
	var frame := node.global_transform
	node.global_transform = Transform3D(turn * frame.basis, turn * (frame.origin - mid) + mid)
