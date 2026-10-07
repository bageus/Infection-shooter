extends RefCounted
const STAMP := preload("res://game/core/vfx/public/surface_stamp.gd")

static func geometry(surfaces: RefCounted, stamps: RefCounted, collider: Node3D, projector: Transform3D, footprint: Vector2, depth: float, skip_glass: bool) -> Array[Dictionary]:
	if not is_instance_valid(collider) or not collider.is_inside_tree():
		return []
	var world := collider.get_world_3d()
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(footprint.x, footprint.y, depth + .025)
	query.shape = box
	query.transform = projector
	query.transform.origin -= projector.basis.z * (depth - .025) * .5
	query.collision_mask = 129
	var bodies: Array[Node3D] = []
	if not collider is CharacterBody3D:
		bodies.append(collider)
	for hit in world.direct_space_state.intersect_shape(query, 32):
		var body := hit.get("collider") as Node3D
		if body != null and not bodies.has(body) and not body is CharacterBody3D and not body.is_in_group("infected_severed_part"):
			bodies.append(body)
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for body in bodies:
		if skip_glass and body.has_method("get_projectile_material") and body.call("get_projectile_material", -1) == "glass":
			continue
		var receivers: Array[MeshInstance3D] = surfaces.receivers(body)
		if receivers.is_empty():
			_collision_geometry(body, projector, footprint, depth, result)
		for receiver in receivers:
			if seen.has(receiver.get_instance_id()):
				continue
			seen[receiver.get_instance_id()] = true
			var mesh: ArrayMesh = stamps.build(receiver, projector, footprint, depth, skip_glass)
			if mesh != null:
				result.append({"anchor": receiver, "mesh": mesh})
			if result.size() >= 12:
				return result
	return result


static func _collision_geometry(body: Node3D, projector: Transform3D, footprint: Vector2, depth: float, result: Array[Dictionary]) -> void:
	# Explicit geometric fallback for procedural floors with a separate MultiMesh renderer.
	for child in body.get_children():
		if not child is CollisionShape3D or not child.shape is BoxShape3D or child.disabled:
			continue
		var receiver := MeshInstance3D.new()
		receiver.set_meta("procedural_floor_proxy", true)
		receiver.mesh = BoxMesh.new()
		receiver.mesh.size = child.shape.size
		receiver.transform = child.global_transform
		var mesh := STAMP.build(receiver, projector, footprint, depth)
		if mesh != null:
			result.append({"anchor": child, "mesh": mesh})
		receiver.free()
