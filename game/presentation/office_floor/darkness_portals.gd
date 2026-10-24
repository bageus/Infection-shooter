extends RefCounted
## Openings (open doors, glass panes) through which the camera sees into a dark room.
## A portal is a rectangle: centre, outward unit normal and two half-extent vectors.

const MAX_PORTALS := 8
const DOOR_HALF_WIDTH := 0.55
const DOOR_HALF_HEIGHT := 1.05
const GLASS_REACH := 0.6


static func make(centre: Vector3, normal: Vector3, half_u: Vector3, half_v: Vector3, room_centre: Vector3) -> Dictionary:
	var outward := Vector3(normal.x, 0.0, normal.z).normalized()
	if outward.dot(Vector3(centre.x - room_centre.x, 0.0, centre.z - room_centre.z)) < 0.0:
		outward = -outward
	return {"centre": centre, "normal": outward, "u": half_u, "v": half_v}


## The opening of a swing door module, in the module's own frame (wall along x, thickness along z).
static func door(door_node: Node3D, room_centre: Vector3) -> Dictionary:
	var wall := (door_node.get_parent() as Node3D) if door_node.name == &"DoorController" else door_node
	var basis := wall.global_basis.orthonormalized()
	var centre := wall.global_position + basis.y * DOOR_HALF_HEIGHT
	return make(centre, basis.z, basis.x * DOOR_HALF_WIDTH, basis.y * DOOR_HALF_HEIGHT, room_centre)


## A glass pane is a thin box collision shape; its two long axes span the opening.
static func pane(shape: CollisionShape3D, room_centre: Vector3) -> Dictionary:
	var box := shape.shape as BoxShape3D
	if box == null:
		return {}
	var axes: Array[Vector3] = [
		shape.global_basis.x * box.size.x * 0.5,
		shape.global_basis.y * box.size.y * 0.5,
		shape.global_basis.z * box.size.z * 0.5,
	]
	var thin := 0
	for index in 3:
		if axes[index].length() < axes[thin].length():
			thin = index
	var normal := axes[thin].normalized()
	if absf(normal.y) > 0.3:
		return {}
	var others: Array[Vector3] = []
	for index in 3:
		if index != thin:
			others.append(axes[index])
	return make(shape.global_position, normal, others[0], others[1], room_centre)
