extends RefCounted
## Edge fitting for planner biomass (ADR-0061): the face of the receiving mesh
## that a patch lies on, as a rectangle in the patch's own plane, plus what
## happens past each side. The shader (biomass_surface.gdshader) clips to it and
## wraps the mass round convex edges (wall top, wall corner, column) or folds it
## onto a concave floor.

## A side whose edge is within this height of the floor meets the floor.
const FLOOR_REACH := 0.15
## How far (patch units) mass may run along the floor from a wall foot.
const FLOOR_SPAN := 2.0
## Longest run (metres) a wrapped edge may follow a neighbouring wall.
const MAX_RUN := 6.0
const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]


## frame: the patch's global transform (x right, y up, z out of the surface).
## space (optional): lets a wrapped edge follow a neighbouring wall that
## continues the end face (an outer corner) further than the receiver is thick.
## Returns {a, b, limit} for the shader, or {} when there is nothing to fit to.
static func compute(frame: Transform3D, anchor: Node3D, space: PhysicsDirectSpaceState3D = null) -> Dictionary:
	var receiver := anchor as MeshInstance3D
	if receiver == null or receiver.mesh == null:
		return {}
	var box := receiver.get_aabb()
	var to_patch := frame.affine_inverse() * receiver.global_transform
	var in_receiver := (receiver.global_basis.transposed() * frame.basis.z).normalized().abs()
	var face := in_receiver.max_axis_index()
	if in_receiver[face] < 0.95:
		return {}
	var first := (face + 1) % 3
	var second := (face + 2) % 3
	var along_first := to_patch.basis * AXES[first] * (box.size[first] * 0.5)
	var along_second := to_patch.basis * AXES[second] * (box.size[second] * 0.5)
	var half := Vector2(Vector2(along_first.x, along_first.y).length(), Vector2(along_second.x, along_second.y).length())
	if half.x < 0.01 or half.y < 0.01:
		return {}
	var u := Vector2(along_first.x, along_first.y) / half.x
	var v := Vector2(-u.y, u.x)
	# A receiver that is not parallel to the patch has no rectangle to fit to.
	if absf(v.dot(Vector2(along_second.x, along_second.y)) / half.y) < 0.9:
		return {}
	var thickness := (to_patch.basis * AXES[face]).length() * box.size[face]
	var center := to_patch * box.get_center()
	var dirs: Array[Vector2] = [u, -u, v, -v]
	var halves := [half.x, half.x, half.y, half.y]
	var limit := Vector4()
	for side in 4:
		var t: Vector2 = dirs[side]
		var edge := frame * Vector3(center.x + t.x * halves[side], center.y + t.y * halves[side], 0.0)
		var outward := (frame.basis * Vector3(t.x, t.y, 0.0)).normalized()
		if outward.y < -0.9 and edge.y < FLOOR_REACH:
			limit[side] = -FLOOR_SPAN
			continue
		limit[side] = maxf(thickness, _run(space, frame, edge, outward) / maxf(frame.basis.z.length(), 0.001))
	return {"a": Vector4(center.x, center.y, u.x, u.y), "b": Vector4(half.x, half.y, 0.0, 0.0), "limit": limit}


# How deep solid geometry continues just inside the edge, behind the patch.
static func _run(space: PhysicsDirectSpaceState3D, frame: Transform3D, edge: Vector3, outward: Vector3) -> float:
	if space == null:
		return 0.0
	var normal := frame.basis.z.normalized()
	var start := edge - outward * 0.02 + normal * 0.01
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start - normal * MAX_RUN, start, 7))
	return clampf((start - hit["position"]).dot(normal), 0.0, MAX_RUN) if not hit.is_empty() else 0.0


static func apply(visual: MeshInstance3D, fit: Dictionary) -> void:
	visual.set_instance_shader_parameter("clip_a", fit.get("a", Vector4()))
	visual.set_instance_shader_parameter("clip_b", fit.get("b", Vector4()))
	visual.set_instance_shader_parameter("clip_limit", fit.get("limit", Vector4()))
