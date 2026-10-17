extends RefCounted
## Bounded placement along the real pane's horizontal axis, including opened doors.
const MAX_MARKS := 12


static func scatter(floor_view: Node3D, panes: Array[MeshInstance3D], direction: Vector3) -> void:
	var emitted := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
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
		var push := floor_view.global_basis.inverse() * direction
		for mark: Dictionary in build_pattern(width, rng):
			if emitted >= MAX_MARKS:
				return
			var offset: Vector2 = mark.offset
			var at := Vector2(center.x, center.z) + axis * offset.x + across * offset.y
			at += Vector2(push.x, push.z).limit_length(1.0) * 0.08
			# Start inside the actual pane span, even when the tail spills past its end.
			var along := clampf(offset.x, -width * 0.45, width * 0.45)
			var start := floor_view.to_global(Vector3(center.x + axis.x * along, 0.22, center.z + axis.y * along))
			var end := floor_view.to_global(Vector3(at.x, 0.22, at.y))
			var ray := PhysicsRayQueryParameters3D.create(start, end, 1)
			if not floor_view.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			var frame: int = mark.frame
			var turns: int = mark.turns
			if frame >= 12:
				if absf(axis.x) > 0.98 or absf(axis.y) > 0.98:
					turns = 0 if absf(axis.x) > absf(axis.y) else 1
				else:
					frame -= 8
			floor_view.call("stamp_glass_debris", at, frame, mark.size, turns)
			emitted += 1


## One independent asymmetric footprint per pane; far chips are fewer and smaller.
## X follows the frame, Y crosses it. Pure placement data enables seeded QA.
static func build_pattern(width: float, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	if not is_finite(width) or width < 0.1 or rng == null:
		return marks
	var extension := Vector2.ZERO
	var mode := rng.randi_range(0, 3) # Neither end, left, right, or both.
	if mode == 1 or mode == 3:
		extension.x = rng.randf_range(0.35, 1.4)
	if mode == 2 or mode == 3:
		extension.y = rng.randf_range(0.35, 1.4)
	var reach := Vector2(rng.randf_range(1.5, 3.3), rng.randf_range(1.5, 3.3))
	var side_bias := rng.randf_range(0.2, 0.8)
	var size_scale := rng.randf_range(0.8, 1.15)
	var far_count := rng.randi_range(1, 2)
	var middle_count := rng.randi_range(2, 3)
	var near_count := MAX_MARKS - far_count - middle_count - rng.randi_range(0, 2)
	var lobe := rng.randf_range(-0.3, 0.3) * width
	for index in near_count + middle_count + far_count:
		var near := index < near_count
		var far := index >= near_count + middle_count
		var sign_side := 1.0 if rng.randf() < side_bias else -1.0
		var distance := rng.randf_range(0.16, 0.58)
		var along := clampf(lobe + rng.randf_range(-0.5, 0.5) * width, -width * 0.5, width * 0.5)
		var frame := rng.randi_range(4, 15)
		var size := rng.randf_range(0.75, 1.2) * size_scale
		if not near:
			distance = rng.randf_range(0.65, 1.1) if not far else rng.randf_range(0.78, 1.0) * (reach.y if sign_side > 0 else reach.x)
			along = rng.randf_range(-width * 0.5 - extension.x, width * 0.5 + extension.y)
			frame = rng.randi_range(0, 3) if far else rng.randi_range(0, 7)
			size = rng.randf_range(0.28, 0.55) if far else rng.randf_range(0.45, 0.75) * size_scale
			# Irregular side tails: no mandatory mirror copy at the other end.
			if far and not extension.is_zero_approx():
				var left := extension.x > 0.0 and (extension.y == 0.0 or rng.randf() < 0.5)
				along = -width * 0.5 - rng.randf_range(0.1, extension.x) if left else width * 0.5 + rng.randf_range(0.1, extension.y)
		marks.append({"offset": Vector2(along, sign_side * distance), "frame": frame,
			"size": size, "turns": rng.randi_range(0, 3)})
	return marks
