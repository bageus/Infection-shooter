extends RefCounted
# Frozen pre-optimization geometry oracle.
const CHAIN_MEMBERSHIP := .5

static func build_piece(data: Dictionary, chain: PackedInt32Array, skeleton: Skeleton3D, materials: Array) -> Dictionary:
	var skinning := {}
	for bone: int in (data.binds as Dictionary):
		skinning[bone] = skeleton.global_transform * skeleton.get_bone_global_pose(bone) * (data.binds[bone] as Transform3D)
	var surfaces_out: Array = []
	var all_points := PackedVector3Array()
	for surface_index in (data.surfaces as Array).size():
		var surface: Dictionary = data.surfaces[surface_index]
		var vertices: PackedVector3Array = surface.vertices
		var bones: PackedInt32Array = surface.bones
		var weights: PackedFloat32Array = surface.weights
		var stride: int = surface.stride
		if bones.is_empty():
			continue
		var member_corners := _member_triangles(data, chain, surface_index)
		var index_map := {}
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var rest := PackedFloat32Array()
		var out_indices := PackedInt32Array()
		var source_normals: PackedVector3Array = surface.normals
		var source_uvs: PackedVector2Array = surface.uvs
		for corner in member_corners:
			if not index_map.has(corner):
				index_map[corner] = positions.size()
				var transform := _blend(skinning, bones, weights, stride, corner)
				positions.append(transform * vertices[corner])
				normals.append((transform.basis * (source_normals[corner] if not source_normals.is_empty() else Vector3.UP)).normalized())
				uvs.append(source_uvs[corner] if not source_uvs.is_empty() else Vector2.ZERO)
				rest.append_array([vertices[corner].x, vertices[corner].y, vertices[corner].z, 1.0])
			out_indices.append(int(index_map[corner]))
		if out_indices.is_empty():
			continue
		all_points.append_array(positions)
		surfaces_out.append({"positions": positions, "normals": normals, "uvs": uvs, "rest": rest, "indices": out_indices, "material": materials[surface_index] if surface_index < materials.size() else null})
	if all_points.is_empty():
		return {}
	var center := Vector3.ZERO
	for point in all_points:
		center += point
	center /= float(all_points.size())
	var mesh := ArrayMesh.new()
	for entry: Dictionary in surfaces_out:
		var positions: PackedVector3Array = entry.positions
		for index in positions.size():
			positions[index] -= center
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = entry.normals
		arrays[Mesh.ARRAY_TEX_UV] = entry.uvs
		arrays[Mesh.ARRAY_CUSTOM0] = entry.rest
		arrays[Mesh.ARRAY_INDEX] = entry.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		if entry.material != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, entry.material)
	var hull := PackedVector3Array()
	var step := maxi(1, floori(all_points.size() / 48.0))
	for index in range(0, all_points.size(), step):
		hull.append(all_points[index] - center)
	return {"mesh": mesh, "center": center, "points": hull}


# Triangle corners of a surface that belong to `chain`, worked out once per
# enemy model and part: every later sever of that part reuses the list.
static func _member_triangles(data: Dictionary, chain: PackedInt32Array, surface_index: int) -> PackedInt32Array:
	var cache: Dictionary = data.get_or_add("piece_cache", {})
	var key := "%s|%d" % [chain, surface_index]
	if cache.has(key):
		return cache[key]
	var surface: Dictionary = data.surfaces[surface_index]
	var vertices: PackedVector3Array = surface.vertices
	var bones: PackedInt32Array = surface.bones
	var weights: PackedFloat32Array = surface.weights
	var stride: int = surface.stride
	var member := PackedByteArray()
	member.resize(vertices.size())
	for index in vertices.size():
		var share := 0.0
		for k in stride:
			if chain.has(bones[index * stride + k]):
				share += weights[index * stride + k]
		member[index] = 1 if share >= CHAIN_MEMBERSHIP else 0
	var corners := PackedInt32Array()
	var source_indices: PackedInt32Array = surface.indices
	for t in range(0, source_indices.size(), 3):
		var a := source_indices[t]
		var b := source_indices[t + 1]
		var c := source_indices[t + 2]
		if member[a] != 0 and member[b] != 0 and member[c] != 0:
			corners.append_array([a, b, c])
	cache[key] = corners
	return corners


static func _blend(skinning: Dictionary, bones: PackedInt32Array, weights: PackedFloat32Array, stride: int, vertex: int) -> Transform3D:
	var basis_sum := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var origin := Vector3.ZERO
	var total := 0.0
	for k in stride:
		var weight := weights[vertex * stride + k]
		var bone := bones[vertex * stride + k]
		if weight <= 0.0 or not skinning.has(bone):
			continue
		var transform: Transform3D = skinning[bone]
		basis_sum.x += transform.basis.x * weight
		basis_sum.y += transform.basis.y * weight
		basis_sum.z += transform.basis.z * weight
		origin += transform.origin * weight
		total += weight
	if total <= 0.0:
		return Transform3D.IDENTITY
	return Transform3D(Basis(basis_sum.x / total, basis_sum.y / total, basis_sum.z / total), origin / total)

