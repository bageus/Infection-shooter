extends RefCounted

const FRAGMENT_SCRIPT = preload("res://game/presentation/office_floor/environment_fragment.gd")


static func find_named(node: Node, wanted: String) -> Node3D:
	if node is Node3D and (node.name.to_lower() == wanted.to_lower() or node.name.to_lower().begins_with(wanted.to_lower() + ".")):
		return node as Node3D
	for child in node.get_children():
		var found := find_named(child, wanted)
		if found != null:
			return found
	return null


static func reveal_meshes(group: Node3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	_collect(group, meshes)
	return meshes


static func _collect(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is Node3D:
		var part := node as Node3D
		if part.scale.length_squared() < 0.000001:
			part.scale = Vector3.ONE
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, meshes)


static func spawn_piece(host: Node3D, mesh: MeshInstance3D, owner: Node3D, stage: int, index: int, direction: Vector3, hit_point: Vector3, blast: bool = false) -> RigidBody3D:
	if not is_instance_valid(host.get("effects_root")):
		return null
	var bounds: AABB = mesh.global_transform * mesh.get_aabb()
	if bounds.size.length_squared() < 0.000001:
		return null
	var fragment := RigidBody3D.new()
	fragment.set_script(FRAGMENT_SCRIPT)
	fragment.name = "Fragment_" + mesh.name
	fragment.set("source", weakref(owner) if owner != null else null)
	fragment.set("piece_name", mesh.name)
	fragment.set("stage_index", stage)
	fragment.set("kickable", index % 3 == 0)
	fragment.mass = clampf(bounds.size.length() * 0.3, 0.1, 3.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(bounds.size.x, 0.02), maxf(bounds.size.y, 0.02), maxf(bounds.size.z, 0.02))
	shape.shape = box
	fragment.add_child(shape)
	var copy := MeshInstance3D.new()
	copy.mesh = mesh.mesh
	copy.material_override = mesh.material_override
	fragment.add_child(copy)
	(host.get("effects_root") as Node3D).add_child(fragment)
	fragment.global_position = bounds.get_center()
	copy.global_transform = mesh.global_transform
	var away := fragment.global_position - hit_point
	away.y = maxf(away.y, 0.1)
	var impulse := (away.normalized() * 0.75 + direction.normalized() * 0.25 + Vector3.UP * 0.35).normalized() * fragment.mass * randf_range(1.5, 3.0) if blast else direction.normalized() * randf_range(0.15, 0.7) + Vector3.UP * 0.3
	fragment.apply_impulse(impulse, (hit_point - fragment.global_position).limit_length(0.3))
	_inherit_motion(host, fragment)
	return fragment


# Pieces of a moving or tipping object keep its motion instead of starting from rest,
# plus a little tumble so they do not slide flat across the floor.
static func _inherit_motion(host: Node3D, fragment: RigidBody3D) -> void:
	if host is RigidBody3D:
		var body := host as RigidBody3D
		var lever := fragment.global_position - body.global_position
		fragment.linear_velocity += body.linear_velocity + body.angular_velocity.cross(lever)
		fragment.angular_velocity += body.angular_velocity
	var tumble := 2.5 / (0.6 + fragment.mass)
	fragment.angular_velocity += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * tumble
