extends RefCounted

const REACH := 1.5
const MOUNT_HEIGHT := 1.25


static func from_floor(item: Node3D, floor_point: Vector3) -> Vector3:
	var origin := floor_point + Vector3.UP * MOUNT_HEIGHT
	var world := item.get_world_3d()
	var nearest := REACH
	var result := Vector3(INF, INF, INF)
	var wall_normal := Vector3.ZERO
	for index in 16:
		var angle := TAU * float(index) / 16.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var target := origin + direction * REACH
		var excluded: Array[RID] = []
		for attempt in 5:
			var ray := PhysicsRayQueryParameters3D.create(origin, target, 3, excluded)
			var hit: Dictionary = world.direct_space_state.intersect_ray(ray)
			if hit.is_empty():
				break
			var body := hit.get("collider") as CollisionObject3D
			if body == null:
				break
			var normal: Vector3 = hit["normal"]
			var distance := origin.distance_to(hit["position"] as Vector3)
			if body is StaticBody3D and absf(normal.y) < 0.35:
				if distance < nearest:
					nearest = distance
					wall_normal = normal
					result = (hit["position"] as Vector3) + normal * 0.025
				break
			excluded.append(body.get_rid())
	if result.is_finite():
		item.set_meta("planning_wall_normal", wall_normal)
	return result
