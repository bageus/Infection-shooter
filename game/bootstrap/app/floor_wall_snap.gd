extends RefCounted

const CLEARANCE := 0.015
const REACH := 0.55


static func position_for(item: Node3D, local_bounds: AABB, position: Vector3) -> Vector3:
	if local_bounds.size.length_squared() < 0.0001:
		return position
	var world_bounds: AABB = Transform3D(item.global_basis, position) * local_bounds
	var center := world_bounds.get_center()
	center.y = world_bounds.position.y + clampf(world_bounds.size.y * 0.5, 0.12, 1.2)
	var extent := world_bounds.size * 0.5
	var reach := maxf(extent.x, extent.z) + REACH
	var exclude: Array[RID] = []
	if item is CollisionObject3D:
		exclude.append((item as CollisionObject3D).get_rid())
	for child in item.find_children("*", "CollisionObject3D", true, false):
		exclude.append((child as CollisionObject3D).get_rid())
	var nearest := REACH
	var result := position
	for step in 8:
		var angle := float(step) * TAU / 8.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var query := PhysicsRayQueryParameters3D.create(center, center + direction * reach, 3, exclude)
		var hit: Dictionary = item.get_world_3d().direct_space_state.intersect_ray(query)
		if not (hit.get("collider") is StaticBody3D):
			continue
		var normal: Vector3 = hit["normal"]
		if absf(normal.y) > 0.2:
			continue
		var face := center - normal * (absf(normal.x) * extent.x + absf(normal.z) * extent.z)
		var gap: float = (face - (hit["position"] as Vector3)).dot(normal)
		if absf(gap) <= REACH and absf(gap) < nearest:
			nearest = absf(gap)
			result = position - normal * (gap - CLEARANCE)
	return result
