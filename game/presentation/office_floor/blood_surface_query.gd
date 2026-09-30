extends Node3D

var collision_mask := 128
var visual_mask := 128
var floor_reach := 3.2
var wall_reach := 3.0
var _awaiting_ready: Dictionary = {}


func watch_environment(node: Node) -> void:
	if node is CharacterBody3D or node.is_in_group("infected") or node.has_meta("blood_effect"):
		return
	_tag_node(node)
	if not node.is_node_ready() and not _awaiting_ready.has(node.get_instance_id()):
		_awaiting_ready[node.get_instance_id()] = true
		node.ready.connect(_retag_ready.bind(weakref(node), node.get_instance_id()), CONNECT_ONE_SHOT)
	if not node.child_entered_tree.is_connected(watch_environment):
		node.child_entered_tree.connect(watch_environment)
	for child in node.get_children():
		watch_environment(child)


func _retag_ready(reference: WeakRef, id: int) -> void:
	_awaiting_ready.erase(id)
	var node := reference.get_ref() as Node
	if node != null:
		_tag_node(node)


func _tag_node(node: Node) -> void:
	if node is PhysicsBody3D and not node is CharacterBody3D:
		(node as PhysicsBody3D).collision_layer |= collision_mask
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers |= visual_mask


func find_floor(position: Vector3, excluded: Array[RID]) -> Dictionary:
	return _cast(position + Vector3.UP * 0.3, position + Vector3.DOWN * floor_reach, excluded, true)


func find_behind(position: Vector3, direction: Vector3, excluded: Array[RID]) -> Dictionary:
	if direction.length_squared() < 0.0001:
		return {}
	var axis := direction.normalized()
	return _cast(position + axis * 0.035, position + axis * wall_reach, excluded, false)


func _cast(start: Vector3, finish: Vector3, excluded: Array[RID], floor_only: bool) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(start, finish, collision_mask)
	query.exclude = excluded.duplicate()
	query.collide_with_areas = false
	for attempt in range(8):
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider := hit.get("collider") as PhysicsBody3D
		var normal: Vector3 = hit["normal"]
		if collider != null and not collider is CharacterBody3D and (not floor_only or normal.y > 0.3):
			return capture(hit["position"], normal, collider)
		if collider == null:
			return {}
		query.exclude.append(collider.get_rid())
	return {}


static func capture(position: Vector3, normal: Vector3, collider: Node3D) -> Dictionary:
	return {"surface": weakref(collider), "local_position": collider.to_local(position), "local_normal": collider.global_basis.transposed() * normal.normalized()}


static func resolve(surface: Dictionary) -> Dictionary:
	if surface.is_empty():
		return {}
	var body := (surface["surface"] as WeakRef).get_ref() as Node3D
	if body == null or body.is_queued_for_deletion() or not body.is_inside_tree():
		return {}
	return {"position": body.to_global(surface["local_position"]), "normal": (body.global_basis.inverse().transposed() * surface["local_normal"]).normalized(), "collider": body}


static func surface_basis(normal: Vector3, direction: Vector3, long_axis_x: bool, angle: float) -> Basis:
	var up := normal.normalized()
	var tangent := direction - up * direction.dot(up)
	if tangent.length_squared() < 0.0001:
		var helper := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		tangent = helper - up * helper.dot(up)
	tangent = tangent.normalized()
	var x := tangent if long_axis_x else up.cross(tangent).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z).rotated(up, angle)


func jitter_surface(surface: Dictionary, amount: float) -> Dictionary:
	var hit := resolve(surface)
	if hit.is_empty():
		return {}
	var basis := surface_basis(hit["normal"], Vector3.ZERO, false, 0.0)
	var point: Vector3 = hit["position"] + basis.x * randf_range(-amount, amount) + basis.z * randf_range(-amount, amount)
	var query := PhysicsRayQueryParameters3D.create(point + basis.y * 0.08, point - basis.y * 0.08, collision_mask)
	var check := get_world_3d().direct_space_state.intersect_ray(query)
	if not check.is_empty() and check.get("collider") == hit["collider"]:
		return capture(check["position"], check["normal"], check["collider"])
	return surface


func fit_quad(surface: Dictionary, basis: Basis, footprint: Vector2) -> Vector2:
	var hit := resolve(surface)
	if hit.is_empty():
		return Vector2.ZERO
	var body: Node3D = hit["collider"]
	var size := footprint
	for attempt in range(4):
		var fits := true
		for corner in [Vector2(-0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5)]:
			var point: Vector3 = hit["position"] + basis.x * corner.x * size.x + basis.z * corner.y * size.y
			var query := PhysicsRayQueryParameters3D.create(point + basis.y * 0.08, point - basis.y * 0.08, collision_mask)
			var check := get_world_3d().direct_space_state.intersect_ray(query)
			if check.is_empty() or check.get("collider") != body or (check["normal"] as Vector3).dot(basis.y) < 0.95:
				fits = false
				break
		if fits:
			return size
		size *= 0.7
	return Vector2.ZERO
