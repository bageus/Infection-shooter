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
## Inner corners: how far in from an edge the probe starts, how far in front
## of the face it runs, and the slack past the edge.
const INSET := 0.3
const PROBE_LIFT := 0.03
const PROBE_SLACK := 0.05
## Floor mass climbing walls: how high above the floor the probes run, how many
## directions, and the step and depth of the stretch probes along a wall.
const WALL_PROBE_HEIGHT := 0.3
const WALL_RAYS := 24
const WALL_STRIDE := 0.25
const WALL_BACK := 0.2
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
	# Rectangle in its own (u, v) frame: low and high bound per axis.
	var lo := [-half.x, -half.y]
	var hi := [half.x, half.y]
	var origin_in_rect := Vector2.ZERO - Vector2(center.x, center.y)
	var here := [origin_in_rect.dot(u), origin_in_rect.dot(v)]
	var scale := maxf(frame.basis.z.length(), 0.001)
	var limit := Vector4()
	for side in 4:
		var t: Vector2 = dirs[side]
		var edge := frame * Vector3(center.x + t.x * halves[side], center.y + t.y * halves[side], 0.0)
		var outward := (frame.basis * Vector3(t.x, t.y, 0.0)).normalized()
		if outward.y < -0.9 and edge.y < FLOOR_REACH:
			limit[side] = -FLOOR_SPAN
			continue
		# A perpendicular wall or box standing in front of this edge: fold onto it.
		var axis := side >> 1
		var sg := 1.0 if side % 2 == 0 else -1.0
		var inset := minf(INSET / scale, halves[side] * 0.5)
		var probe: Array = [clampf(here[0], lo[0] * 0.9, hi[0] * 0.9), clampf(here[1], lo[1] * 0.9, hi[1] * 0.9)]
		probe[axis] = sg * (halves[side] - inset)
		var start := frame * Vector3(center.x + u.x * probe[0] - u.y * probe[1], center.y + u.y * probe[0] + u.x * probe[1], 0.0) + frame.basis.z.normalized() * PROBE_LIFT
		var reach := inset * scale + PROBE_SLACK
		var met := _meet(space, start, outward, reach)
		if met >= 0.0:
			var at: float = probe[axis] + sg * met / scale
			if sg > 0.0:
				hi[axis] = minf(hi[axis], at)
			else:
				lo[axis] = maxf(lo[axis], at)
			limit[side] = -FLOOR_SPAN
			continue
		limit[side] = maxf(thickness, _run(space, frame, edge, outward) / scale)
	# Trimmed bounds back to centre and half sizes.
	var mid := Vector2((lo[0] + hi[0]) * 0.5, (lo[1] + hi[1]) * 0.5)
	var shifted := Vector2(center.x, center.y) + u * mid.x + Vector2(-u.y, u.x) * mid.y
	return {"a": Vector4(shifted.x, shifted.y, u.x, u.y), "b": Vector4((hi[0] - lo[0]) * 0.5, (hi[1] - lo[1]) * 0.5, 0.0, 0.0), "limit": limit}


# Distance along dir to a surface that stands across it (a perpendicular wall,
# a box side), or -1.0 when the way is free.
static func _meet(space: PhysicsDirectSpaceState3D, start: Vector3, dir: Vector3, reach: float) -> float:
	if space == null:
		return -1.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start, start + dir * reach, 7))
	if hit.is_empty() or absf((hit["normal"] as Vector3).dot(dir)) < 0.7:
		return -1.0
	return (hit["position"] - start).dot(dir)


# How deep solid geometry continues just inside the edge, behind the patch.
static func _run(space: PhysicsDirectSpaceState3D, frame: Transform3D, edge: Vector3, outward: Vector3) -> float:
	if space == null:
		return 0.0
	var normal := frame.basis.z.normalized()
	var start := edge - outward * 0.02 + normal * 0.01
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(start - normal * MAX_RUN, start, 7))
	return clampf((start - hit["position"]).dot(normal) - 0.01, 0.0, MAX_RUN) if not hit.is_empty() else 0.0


## Floor mass: the walls (up to two) that stand in the patch's footprint and the
## mass climbs, as shader values {p0, r0, p1, r1} in patch units. rect is the
## patch (or fused group) in local units. A wall only counts along the stretch
## where it really stands, so a table end or a column does not bend the whole
## patch.
static func compute_floor(frame: Transform3D, rect: Rect2, space: PhysicsDirectSpaceState3D) -> Dictionary:
	if space == null:
		return {}
	var scale := maxf(frame.basis.x.length(), 0.001)
	var up := frame.basis.z.normalized()
	if up.y < 0.9:
		return {}
	var centre_local := rect.get_center()
	var origin := frame * Vector3(centre_local.x, centre_local.y, 0.0) + up * WALL_PROBE_HEIGHT
	var radius := rect.size.length() * 0.5 * scale + PROBE_SLACK
	var seen: Array[Dictionary] = []
	for step in WALL_RAYS:
		var angle := TAU * float(step) / WALL_RAYS
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * radius, 7))
		if hit.is_empty() or absf((hit["normal"] as Vector3).y) > 0.35 or hit["collider"] is CharacterBody3D:
			continue
		var flat := Vector2((hit["normal"] as Vector3).x, (hit["normal"] as Vector3).z)
		if flat.is_zero_approx():
			continue
		seen.append({"n": -flat.normalized(), "at": Vector2((hit["position"] as Vector3).x, (hit["position"] as Vector3).z), "range": origin.distance_to(hit["position"])})
	seen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["range"] < b["range"])
	var result := {}
	var chosen: Array[Dictionary] = []
	for candidate in seen:
		var distinct := true
		for taken in chosen:
			distinct = distinct and (candidate["n"] as Vector2).dot(taken["n"]) < 0.9
		if distinct and chosen.size() < 2:
			chosen.append(candidate)
	for index in chosen.size():
		var wall := _wall_plane(frame, scale, origin.y, chosen[index], radius, space)
		if not wall.is_empty():
			result["p%d" % index] = wall["p"]
			result["r%d" % index] = wall["r"]
	return result


# One wall as a plane in patch units plus the stretch of it that is solid.
static func _wall_plane(frame: Transform3D, scale: float, height: float, wall: Dictionary, radius: float, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var n: Vector2 = wall["n"]
	var at: Vector2 = wall["at"]
	var origin := Vector2(frame.origin.x, frame.origin.z)
	var x := Vector2(frame.basis.x.x, frame.basis.x.z)
	var y := Vector2(frame.basis.y.x, frame.basis.y.z)
	var normal_local := Vector2(n.dot(x), n.dot(y)) / scale
	if normal_local.length() < 0.5:
		return {}
	var tangent := Vector2(-n.y, n.x)
	var span := [0.0, 0.0]
	for side in 2:
		var direction := -1.0 if side == 0 else 1.0
		for step in range(1, ceili(radius / WALL_STRIDE) + 1):
			var point := at + tangent * (direction * step * WALL_STRIDE) - n * WALL_BACK
			var from := Vector3(point.x, height, point.y)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(n.x, 0.0, n.y) * (WALL_BACK + 0.06), 7))
			if hit.is_empty() or hit["collider"] is CharacterBody3D:
				break
			var flat := Vector2((hit["normal"] as Vector3).x, (hit["normal"] as Vector3).z)
			if absf((hit["normal"] as Vector3).y) > 0.35 or flat.dot(-n) < 0.8 * flat.length():
				break
			span[side] = direction * step * WALL_STRIDE
	var centre := tangent.dot(at - origin)
	var low: float = centre + span[0] - WALL_STRIDE * 0.5
	var high: float = centre + span[1] + WALL_STRIDE * 0.5
	# The shader measures along (-n.y, n.x) of the patch frame, which mirrors when the frame does.
	var tangent_local := Vector2(tangent.dot(x), tangent.dot(y)) / scale
	if tangent_local.dot(Vector2(-normal_local.y, normal_local.x)) < 0.0:
		var swapped := -low
		low = -high
		high = swapped
	var offset := n.dot(at - origin) / scale
	return {"p": Vector4(normal_local.x, normal_local.y, offset, FLOOR_SPAN), "r": Vector4(low / scale, high / scale, 0.0, 0.0)}


## The level's floor rectangle as world_clip (min x, min z, max x, max z).
static func world_clip(bounds: Rect2) -> Vector4:
	return Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y) if bounds.has_area() else Vector4()


## Gives the visual its own copy of the patch material carrying this piece's
## clip (fit from compute / compute_floor), level bounds and flattening, or the
## shared one again when nothing is set. Per-piece uniforms instead of instance
## uniforms: the global instance buffer holds 4096 slots on some hardware.
static func style(visual: MeshInstance3D, fit: Dictionary, world: Vector4, depth_scale: float) -> void:
	var base: ShaderMaterial = null
	if visual.mesh != null and visual.mesh.get_surface_count() > 0:
		base = visual.mesh.surface_get_material(0) as ShaderMaterial
	if base == null:
		return
	var plain := fit.is_empty() and world == Vector4() and is_equal_approx(depth_scale, 1.0)
	if plain:
		visual.material_override = null
		return
	var own := visual.material_override as ShaderMaterial
	if own == null or own.get_meta(&"biomass_base", null) != base:
		own = base.duplicate() as ShaderMaterial
		own.set_meta(&"biomass_base", base)
		visual.material_override = own
	own.set_shader_parameter("clip_a", fit.get("a", Vector4()))
	own.set_shader_parameter("clip_b", fit.get("b", Vector4()))
	own.set_shader_parameter("clip_limit", fit.get("limit", Vector4()))
	own.set_shader_parameter("world_clip", world)
	own.set_shader_parameter("wall_p0", fit.get("p0", Vector4()))
	own.set_shader_parameter("wall_r0", fit.get("r0", Vector4()))
	own.set_shader_parameter("wall_p1", fit.get("p1", Vector4()))
	own.set_shader_parameter("wall_r1", fit.get("r1", Vector4()))
	own.set_shader_parameter("depth_scale", depth_scale)
	own.set_shader_parameter("support_texture", fit.get("support"))
	own.set_shader_parameter("support_rect", fit.get("support_rect", Vector4()))


## Current value of a clip uniform of the visual (default when unset).
static func value(visual: MeshInstance3D, name: String) -> Variant:
	var own := visual.material_override as ShaderMaterial
	var found: Variant = own.get_shader_parameter(name) if own != null else null
	if found == null and name != "support_texture":
		if name == "depth_scale":
			return 1.0
		return Vector4()
	return found
