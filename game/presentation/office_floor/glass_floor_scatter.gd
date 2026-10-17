extends RefCounted
## Bounded placement along the real pane's horizontal axis, including opened doors.
const MAX_MARKS := 12


static func scatter(floor_view: Node3D, panes: Array[MeshInstance3D], direction: Vector3) -> void:
	var emitted := 0
	for pane in panes:
		if not is_instance_valid(pane) or pane.mesh == null:
			continue
		var bounds := pane.get_aabb()
		var pose := floor_view.global_transform.affine_inverse() * pane.global_transform
		if not pose.is_finite():
			continue
		var center := pose * bounds.get_center()
		var axis := Vector2.ZERO
		for edge in [pose.basis.x * bounds.size.x, pose.basis.y * bounds.size.y, pose.basis.z * bounds.size.z]:
			var horizontal := Vector2(edge.x, edge.z)
			if horizontal.length_squared() > axis.length_squared():
				axis = horizontal
		var width := axis.length()
		if width < 0.1 or center.y < -0.2 or center.y > 4.0:
			continue
		axis = axis.normalized()
		var across := Vector2(-axis.y, axis.x)
		var samples := clampi(ceili(width / 0.65), 1, 5)
		for index in samples:
			for side in [-1.0, 1.0]:
				if emitted >= MAX_MARKS:
					return
				var along := ((index + 0.5) / samples - 0.5) * width
				var at: Vector2 = Vector2(center.x, center.z) + axis * along + across * side * randf_range(0.28, 0.48)
				var start := floor_view.to_global(Vector3(center.x + axis.x * along, 0.22, center.z + axis.y * along))
				var end := floor_view.to_global(Vector3(at.x, 0.22, at.y))
				# Do not spill the pattern through an opaque wall near the frame.
				var ray := PhysicsRayQueryParameters3D.create(start, end, 1)
				if not floor_view.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
					continue
				var turns := randi_range(0, 3)
				var frame := randi_range(0, 11)
				# Long strips suit axis-aligned frames. Round patches suit other angles.
				if absf(axis.x) > 0.98 or absf(axis.y) > 0.98:
					frame = randi_range(12, 15) if index % 2 == 0 else frame
					turns = 0 if absf(axis.x) > absf(axis.y) else 1
				var push := floor_view.global_basis.inverse() * direction
				at += Vector2(push.x, push.z).limit_length(1.0) * 0.08
				floor_view.call("stamp_glass_debris", at, frame, randf_range(0.85, 1.2), turns)
				emitted += 1
