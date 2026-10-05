extends RefCounted

static func obstruction(weapon: Node3D, muzzle: Node3D, shooter: CollisionObject3D) -> Dictionary:
	if shooter == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(shooter.global_position, muzzle.global_position, 1)
	var excluded: Array[RID] = [shooter.get_rid()]
	query.hit_from_inside = true
	for attempt in 16:
		query.exclude = excluded
		var hit := weapon.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var body: Node = hit["collider"]
		var material := str(body.call("get_projectile_material", hit.get("shape", -1))) if body.has_method("get_projectile_material") else "solid"
		if material in ["solid", "concrete"]:
			if (hit["normal"] as Vector3).is_zero_approx():
				hit["normal"] = (shooter.global_position - muzzle.global_position).normalized()
			return hit
		# A penetrable object in front of the wall must not conceal that wall.
		excluded.append(hit["rid"])
	return {}
