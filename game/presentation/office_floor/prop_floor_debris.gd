extends RefCounted
## One prop's bounded visual emission history and local geometry capture.
const RECIPE := preload("res://game/presentation/office_floor/prop_debris_recipe.gd")
var floor_view: Node3D
var _events: Dictionary = {}
var _rare_used := false


func emit(host: Node3D, model: String, event: String, point: Vector3, direction: Vector3) -> bool:
	if not is_instance_valid(floor_view) or _events.has(event) or _events.size() >= 4:
		return false
	var recipe := RECIPE.for_model(model, event)
	if _rare_used and event != "rupture":
		recipe = recipe.filter(func(kind: String) -> bool: return kind != "extinguisher")
	if recipe.is_empty():
		return false
	_events[event] = true
	_rare_used = _rare_used or "extinguisher" in recipe
	var excluded: Array[RID] = []
	if host is CollisionObject3D:
		excluded.append((host as CollisionObject3D).get_rid())
	for body in host.find_children("*", "CollisionObject3D", true, false):
		excluded.append((body as CollisionObject3D).get_rid())
	var bounds := AABB()
	var found := false
	var count := 0
	for node in host.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or mesh.has_meta("planning_bounds_excluded"):
			continue
		var area: AABB = (floor_view.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = bounds.merge(area) if found else area
		found = true
		count += 1
		if count >= 48:
			break
	var at := floor_view.to_local(point)
	var footprint := Vector2.ONE * 0.6
	if found and event != "rupture":
		at = bounds.get_center()
		footprint = Vector2(bounds.size.x, bounds.size.z).clamp(Vector2.ONE * 0.3, Vector2.ONE * 5.0)
	floor_view.call("scatter_prop_debris", at, footprint, recipe, direction, excluded)
	return true
