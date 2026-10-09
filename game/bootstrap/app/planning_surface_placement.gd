extends RefCounted
## Align the lowest visible vertex or back plane, rather than the model pivot.
const BASE_FLOOR_TOP := 0.0135 # base_floor tile_y .001 + half its .025 thickness
const CLEARANCE := 0.002

static func ground_height(node: Node3D, bounds: AABB, surface_y: float) -> float:
	var world_bounds := Transform3D(node.global_basis, Vector3.ZERO) * bounds
	return maxf(surface_y, BASE_FLOOR_TOP) - world_bounds.position.y + CLEARANCE


static func mount(node: Node3D, bounds: AABB, normal: Vector3) -> void:
	node.rotation.y = atan2(normal.x, normal.z)
	var back := INF
	for index in 8:
		back = minf(back, (node.global_basis * bounds.get_endpoint(index)).dot(normal))
	node.global_position += normal * (WALL_CLEARANCE - back)

const WALL_CLEARANCE := 0.0005

static func wall_grid(point: Vector3, normal: Vector3, step: float = 0.25) -> Vector3:
	var n := Vector3(normal.x, 0.0, normal.z).normalized()
	var tangent := Vector3(n.z, 0.0, -n.x)
	return n * point.dot(n) + tangent * snappedf(point.dot(tangent), step) + Vector3.UP * snappedf(point.y, step)

static func visual_wall_point(point: Vector3, normal: Vector3, collider: Node3D) -> Vector3:
	if collider == null:
		return point
	var root := collider
	for level in 3:
		if root.has_meta("planning_scene_path") or root.is_in_group("camera_occluder") or not root.get_parent() is Node3D:
			break
		root = root.get_parent() as Node3D
	var nearest := 0.10
	var correction := 0.0
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		if visual.mesh == null or not visual.is_visible_in_tree() or visual.has_meta("planning_selection_highlight"):
			continue
		if visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var box := visual.global_transform * visual.get_aabb()
		if not box.grow(0.10).has_point(point):
			continue
		var face := -INF
		for index in 8:
			face = maxf(face, (visual.global_transform * visual.get_aabb().get_endpoint(index)).dot(normal))
		var delta := face - point.dot(normal)
		if absf(delta) < nearest:
			nearest = absf(delta)
			correction = delta
	return point + normal * correction
