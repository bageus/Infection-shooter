extends RefCounted
## Align the lowest visible vertex or back plane, rather than the model pivot.
const BASE_FLOOR_TOP := 0.0135 # base_floor tile_y .001 + half its .025 thickness
const CLEARANCE := 0.002

static func ground_height(node: Node3D, bounds: AABB, surface_y: float) -> float:
	var world_bounds := Transform3D(node.global_basis, Vector3.ZERO) * bounds
	return maxf(surface_y, BASE_FLOOR_TOP) - world_bounds.position.y + CLEARANCE


static func mount(node: Node3D, bounds: AABB, normal: Vector3) -> void:
	node.rotation.y = atan2(normal.x, normal.z)
	var back := INF
	for index in 8:
		back = minf(back, (node.global_basis * bounds.get_endpoint(index)).dot(normal))
	node.global_position += normal * (CLEARANCE - back)
