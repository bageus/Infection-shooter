extends RefCounted
## Probe actual collision volumes instead of assuming a model's origin is its floor.
static func lift_embedded(body: RigidBody3D) -> void:
	var bounds := AABB()
	var found := false
	for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
		if shape.disabled or shape.get_parent() != body or shape.shape == null:
			continue
		var world := shape.global_transform * shape.shape.get_debug_mesh().get_aabb()
		bounds = bounds.merge(world) if found else world
		found = true
	if not found:
		return
	var top := body.global_position + Vector3.UP * 0.1
	var bottom := Vector3(top.x, bounds.position.y - 0.1, top.z)
	if bottom.y >= top.y:
		return
	var ray := PhysicsRayQueryParameters3D.create(top, bottom, body.collision_mask, [body.get_rid()])
	var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < 0.7:
		return
	var lift := float(hit.position.y) - bounds.position.y
	if lift > 0.002 and lift < maxf(0.5, bounds.size.y + 0.05):
		body.global_position.y += lift + 0.005


static func may_move(body: RigidBody3D) -> bool:
	if body.freeze:
		return false
	if body.linear_velocity.length_squared() > 0.01 or body.angular_velocity.length_squared() > 0.01:
		return true
	var params := PhysicsTestMotionParameters3D.new()
	params.from = body.global_transform
	params.motion = Vector3.DOWN * 0.06
	params.margin = 0.001
	params.recovery_as_collision = true
	var result := PhysicsTestMotionResult3D.new()
	if not PhysicsServer3D.body_test_motion(body.get_rid(), params, result):
		return true
	var prepared := body.has_meta("planning_settled_transform") and body.get_meta("planning_settled_transform") == body.transform
	if body.sleeping and prepared:
		for index in result.get_collision_count():
			if result.get_collision_normal(index).dot(Vector3.UP) > 0.1:
				return false
	if result.get_travel().y > 0.01 or result.get_travel().y < -0.025:
		return true
	var support := false
	for index in result.get_collision_count():
		support = support or result.get_collision_normal(index).dot(Vector3.UP) > 0.7
	if not support or (body.global_basis.orthonormalized().y.dot(Vector3.UP) < 0.999 and not prepared):
		return true
	var space := body.get_world_3d().direct_space_state
	for shape: CollisionShape3D in body.find_children("*", "CollisionShape3D", true, false):
		if shape.disabled or shape.get_parent() != body or shape.shape == null:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.transform.basis *= Basis.from_scale(Vector3.ONE * 0.96)
		query.collision_mask = body.collision_mask
		query.exclude = [body.get_rid()]
		if not space.intersect_shape(query, 1).is_empty():
			return true
	return false


static func supported(samples: Array) -> bool:
	var bone_support := {}
	for sample: Node3D in samples:
		if not is_instance_valid(sample):
			continue
		if sample is PhysicalBone3D:
			var group := sample.get_parent()
			bone_support[group] = bool(bone_support.get(group, false)) or _bone_supported(sample)
			continue
		if not sample is RigidBody3D or sample.sleeping:
			continue
		var params := PhysicsTestMotionParameters3D.new()
		params.from = sample.global_transform
		params.motion = Vector3.DOWN * 0.04
		params.margin = 0.001
		params.recovery_as_collision = true
		var result := PhysicsTestMotionResult3D.new()
		if not PhysicsServer3D.body_test_motion(sample.get_rid(), params, result):
			return false
		var support := false
		for index in result.get_collision_count():
			support = support or result.get_collision_normal(index).dot(Vector3.UP) > 0.7
		# Recovery can exceed requested travel because of Jolt convex margins.
		if not support or result.get_travel().y < -0.08:
			return false
	return not bone_support.values().has(false)


static func resting(samples: Array) -> bool:
	var has_body := false
	for sample: Node3D in samples:
		if not is_instance_valid(sample) or not (sample is RigidBody3D or sample is PhysicalBone3D):
			return false
		has_body = true
		var linear: Vector3 = PhysicsServer3D.body_get_state(sample.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
		var angular: Vector3 = PhysicsServer3D.body_get_state(sample.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
		if linear.length_squared() >= (0.0225 if sample is PhysicalBone3D else 0.01) or angular.length_squared() >= 0.02:
			return false
	return has_body


static func _bone_supported(bone: PhysicalBone3D) -> bool:
	for child in bone.get_children():
		if not child is CollisionShape3D or child.shape == null or child.disabled:
			continue
		var bounds: AABB = child.global_transform * child.shape.get_debug_mesh().get_aabb()
		var from: Vector3 = child.global_position + Vector3.UP * 0.01
		var to := Vector3(from.x, bounds.position.y - 0.12, from.z)
		if not bone.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty():
			return true
	return false
