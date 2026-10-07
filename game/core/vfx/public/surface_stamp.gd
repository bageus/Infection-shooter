extends RefCounted
## Stateless, clipped texture projection onto real receiver triangles.
const MAX_TRIANGLES := 4096

static func build(receiver: MeshInstance3D, projector: Transform3D, size: Vector2, depth: float, skip_glass: bool = false) -> ArrayMesh:
	return _build(receiver, projector, size, depth, skip_glass, [])


# Prepared surfaces are supplied only by the core.vfx owned-cache adapter.
static func _build(receiver: MeshInstance3D, projector: Transform3D, size: Vector2, depth: float, skip_glass: bool, prepared: Array) -> ArrayMesh:
	if receiver.mesh == null or absf(_transform(receiver).basis.determinant()) < 1e-10:
		return null
	var to_projector := projector.affine_inverse() * _transform(receiver)
	var bounds := to_projector * receiver.get_aabb()
	var volume := AABB(Vector3(-size.x / 2, -size.y / 2, -depth), Vector3(size.x, size.y, depth + .025))
	if not bounds.intersects(volume):
		return null
	var output := {"positions": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array()}
	for surface in receiver.mesh.get_surface_count():
		if skip_glass and _glass(receiver, surface):
			continue
		_project_surface(receiver, surface, projector, to_projector, volume, size, output, prepared[surface] if not prepared.is_empty() else {})
		if output.positions.size() >= MAX_TRIANGLES * 3:
			break
	if output.positions.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = output.positions
	arrays[Mesh.ARRAY_NORMAL] = output.normals
	arrays[Mesh.ARRAY_TEX_UV] = output.uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _project_surface(receiver: MeshInstance3D, surface: int, projector: Transform3D, to_projector: Transform3D, volume: AABB, size: Vector2, output: Dictionary, prepared: Dictionary) -> void:
	var arrays: Array = prepared["arrays"] if not prepared.is_empty() else receiver.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	var normal_transform := _transform(receiver).basis.inverse().transposed()
	var to_local := _transform(receiver).affine_inverse()
	var candidates: Variant = prepared["candidates"] if not prepared.is_empty() else range(0, count - 2, 3)
	for triangle: int in candidates:
		var ids := [indices[triangle], indices[triangle + 1], indices[triangle + 2]] if not indices.is_empty() else [triangle, triangle + 1, triangle + 2]
		var polygon := PackedVector3Array([to_projector * vertices[ids[0]], to_projector * vertices[ids[1]], to_projector * vertices[ids[2]]])
		var tri_bounds := AABB(polygon[0], Vector3.ZERO).expand(polygon[1]).expand(polygon[2]).grow(.00001)
		if not tri_bounds.intersects(volume):
			continue
		var local_normal := (vertices[ids[1]] - vertices[ids[0]]).cross(vertices[ids[2]] - vertices[ids[0]]).normalized()
		if not normals.is_empty():
			local_normal = (normals[ids[0]] + normals[ids[1]] + normals[ids[2]]).normalized()
		var world_normal := (normal_transform * local_normal).normalized()
		if world_normal.dot(projector.basis.z) <= .035:
			continue # No rear-face stain or degenerate projection on a perpendicular edge.
		for axis in 3:
			polygon = _clip(polygon, axis, volume.position[axis], true)
			polygon = _clip(polygon, axis, volume.end[axis], false)
		if polygon.size() < 3:
			continue
		var offset := .018 if world_normal.y > .85 and bool(receiver.get_meta("procedural_floor_proxy", false)) else .0015
		for fan in range(1, polygon.size() - 1):
			for point in [polygon[0], polygon[fan], polygon[fan + 1]]:
				output.positions.append(to_local * (projector * point + world_normal * offset))
				output.normals.append(local_normal)
				output.uvs.append(Vector2(point.x / size.x + .5, .5 - point.y / size.y))
		if output.positions.size() >= MAX_TRIANGLES * 3:
			return


static func _clip(input: PackedVector3Array, axis: int, limit: float, minimum: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	if input.is_empty():
		return result
	var previous := input[input.size() - 1]
	var before := previous[axis] >= limit if minimum else previous[axis] <= limit
	for current in input:
		var inside := current[axis] >= limit if minimum else current[axis] <= limit
		if inside != before:
			result.append(previous.lerp(current, (limit - previous[axis]) / (current[axis] - previous[axis])))
		if inside:
			result.append(current)
		previous = current
		before = inside
	return result


static func _glass(receiver: MeshInstance3D, surface: int) -> bool:
	var material := receiver.get_active_material(surface)
	var label := receiver.name.to_lower() + (material.resource_name.to_lower() if material != null else "")
	return "glass" in label or "mirror" in label or (material is BaseMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a < .9)


static func _transform(receiver: MeshInstance3D) -> Transform3D:
	return receiver.global_transform if receiver.is_inside_tree() else receiver.transform
