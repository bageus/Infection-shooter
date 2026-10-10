extends RefCounted
## Flush side/back placement against the visible wall plane, including corners.
const SURFACE := preload("res://game/bootstrap/app/planning_surface_placement.gd")
const CLEARANCE := 0.0005
const REACH := 0.55

static func position_for(item: Node3D, local_bounds: AABB, position: Vector3) -> Vector3:
	if local_bounds.size.length_squared() < 0.0001:
		return position
	var exclude: Array[RID] = []
	if item is CollisionObject3D:
		exclude.append((item as CollisionObject3D).get_rid())
	for child in item.find_children("*", "CollisionObject3D", true, false):
		exclude.append((child as CollisionObject3D).get_rid())
	var result := position
	var directions: Array[Vector3] = [item.global_basis.x.normalized(), -item.global_basis.x.normalized(), -item.global_basis.z.normalized()]
	for direction in directions:
		var frame := Transform3D(item.global_basis, result)
		var center := frame * local_bounds.get_center()
		var support := 0.0
		for index in 8:
			support = maxf(support, ((frame * local_bounds.get_endpoint(index)) - center).dot(direction))
		var query := PhysicsRayQueryParameters3D.create(center, center + direction * (support + REACH), 3, exclude)
		var hit: Dictionary = item.get_world_3d().direct_space_state.intersect_ray(query)
		if not (hit.get("collider") is StaticBody3D):
			continue
		var normal: Vector3 = hit["normal"]
		if normal.dot(-direction) < .999:
			continue # A diagonal wall requires rotating the object, not AABB snapping.
		var contact := SURFACE.visual_wall_point(hit["position"], normal, hit["collider"])
		var gap := (center + direction * support - contact).dot(normal)
		if absf(gap) <= REACH:
			result -= normal * (gap - CLEARANCE)
	return result
