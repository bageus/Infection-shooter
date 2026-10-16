extends RefCounted
## One reverse ray from outside the hit shape's bounds; never guess an exit.

static func surface(collider: Object, shape_index: int, entry: Vector3, direction: Vector3, excluded: Array[RID]) -> Dictionary:
	if not collider is CollisionObject3D or shape_index < 0:
		return {}
	var body := collider as CollisionObject3D
	var owner := body.shape_find_owner(shape_index)
	var shape: Shape3D
	for index in body.shape_owner_get_shape_count(owner):
		if body.shape_owner_get_shape_index(owner, index) == shape_index:
			shape = body.shape_owner_get_shape(owner, index)
			break
	if shape == null:
		return {}
	var bounds := shape.get_debug_mesh().get_aabb()
	var transform := body.global_transform * body.shape_owner_get_transform(owner)
	var far_projection := entry.dot(direction)
	for index in 8:
		far_projection = maxf(far_projection, (transform * bounds.get_endpoint(index)).dot(direction))
	var start := entry + direction * (far_projection - entry.dot(direction) + 0.005)
	var query := PhysicsRayQueryParameters3D.create(start, entry - direction * 0.005, body.collision_layer)
	query.exclude = excluded
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.get("collider") != body or int(hit.get("shape", -1)) != shape_index:
		return {}
	var point: Vector3 = hit["position"]
	if (point - entry).dot(direction) <= 0.001:
		return {}
	return {"position": point}
