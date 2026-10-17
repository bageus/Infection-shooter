extends RefCounted
## Release this module's frozen wall props touching a destroyed partition's faces.
const CONTACT_TOLERANCE := .06

static func drop_attached(partition: Node3D, meshes: Array[MeshInstance3D]) -> void:
	var inverse := partition.global_transform.affine_inverse()
	var backing := _bounds(meshes, inverse)
	if backing.size == Vector3.ZERO:
		return
	# Work in the backing's axes: a world AABB also catches unrelated nearby walls.
	for node in partition.get_tree().get_nodes_in_group(&"wall_mounted_props"):
		var prop := node as RigidBody3D
		if prop == null or prop == partition or not prop.freeze or prop.is_queued_for_deletion():
			continue
		if absf(prop.global_basis.z.normalized().dot(partition.global_basis.z.normalized())) < .9:
			continue
		var parts: Array[MeshInstance3D] = prop.get("_shape_meshes")
		var item := _bounds(parts, inverse)
		if item.size != Vector3.ZERO and backing.grow(CONTACT_TOLERANCE).intersects(item):
			prop.call("fall_off_with_glass")


static func _bounds(meshes: Array[MeshInstance3D], inverse: Transform3D) -> AABB:
	var result := AABB()
	for mesh in meshes:
		if not is_instance_valid(mesh) or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var box: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		result = box if result.size == Vector3.ZERO else result.merge(box)
	return result
