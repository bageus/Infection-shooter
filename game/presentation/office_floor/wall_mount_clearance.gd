extends RefCounted
## A wall item whose collision is buried in the wall or column behind it cannot be shot: the bullet stops
## at the support first. Slides it out along its front (+Z) until a ray from the front reaches it.


static func surface(prop: Node3D) -> void:
	if not is_instance_valid(prop) or not prop.is_inside_tree() or not prop.freeze:
		return
	await prop.get_tree().physics_frame
	if not is_instance_valid(prop) or not prop.is_inside_tree():
		return
	var axis := prop.global_basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(prop.global_position + axis * 0.6, prop.global_position, 7)
	var hit := prop.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider is StaticBody3D:
		return # Only a fixed wall or column can bury it.
	var gap := prop.global_position.distance_to(hit.position)
	if gap < 0.3:
		prop.global_position += axis * (gap + 0.03)
