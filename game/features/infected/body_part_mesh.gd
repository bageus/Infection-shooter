extends RefCounted
## Mesh-side helpers for destructible enemy bodies (ADR-0017).
##
## For every skinned enemy mesh (cached per mesh resource) this keeps the
## bind-pose vertices and their skeleton bone weights, adds the rest position
## as CUSTOM0 for the wound shader, measures limb thickness and builds static
## meshes of a severed part in its current pose.

const WOUND_SHADER := preload("res://game/features/infected/body_wound.gdshader")
const TOPOLOGY := preload("res://game/features/infected/body_part_topology.gd")

static var _cache: Dictionary = {}


# Returns {mesh, surfaces:[{vertices, normals, tangents, uvs, bones, weights,
# indices, stride}], binds:{bone: Transform3D}} and swaps in the CUSTOM0 mesh.
static func prepare(mesh_instance: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var source := mesh_instance.mesh as ArrayMesh
	if source == null:
		return {}
	var key := source.get_instance_id()
	if source.has_meta("body_part_source"):
		key = int(source.get_meta("body_part_source"))
	if _cache.has(key):
		var cached: Dictionary = _cache[key]
		mesh_instance.mesh = cached.mesh
		return cached
	var bind_bones := _bind_bones(mesh_instance, skeleton)
	var converted := ArrayMesh.new()
	converted.set_meta("body_part_source", key)
	var surfaces: Array = []
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var custom := PackedFloat32Array()
		custom.resize(vertices.size() * 4)
		for index in vertices.size():
			custom[index * 4] = vertices[index].x
			custom[index * 4 + 1] = vertices[index].y
			custom[index * 4 + 2] = vertices[index].z
			custom[index * 4 + 3] = 1.0
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		var format := source.surface_get_format(surface)
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		converted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		var source_material := mesh_instance.get_active_material(surface)
		converted.surface_set_material(surface, source_material if source_material != null else StandardMaterial3D.new())
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var mapped := PackedInt32Array()
		mapped.resize(bones.size())
		for index in bones.size():
			mapped[index] = int(bind_bones.get(bones[index], {"bone": -1}).bone)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(vertices.size())
			for index in vertices.size():
				indices[index] = index
		surfaces.append({
			"vertices": vertices,
			"normals": arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array(),
			"uvs": arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array(),
			"bones": mapped,
			"weights": arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array(),
			"indices": indices,
			"stride": 8 if format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4,
		})
	var binds := {}
	for bind: int in bind_bones:
		var entry: Dictionary = bind_bones[bind]
		if int(entry.bone) >= 0:
			binds[int(entry.bone)] = entry.pose
	var data := {"mesh": converted, "surfaces": surfaces, "binds": binds, "bone_stats": {}}
	_cache[key] = data
	mesh_instance.mesh = converted
	return data


static func _bind_bones(mesh_instance: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	var skin := mesh_instance.skin
	if skin == null:
		for bone in skeleton.get_bone_count():
			result[bone] = {"bone": bone, "pose": skeleton.get_bone_global_rest(bone).affine_inverse()}
		return result
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		result[bind] = {"bone": bone, "pose": skin.get_bind_pose(bind)}
	return result


# Bind-space joint of a bone (where the bone starts in the rest mesh).
static func joint(data: Dictionary, bone: int, skeleton: Skeleton3D) -> Vector3:
	if (data.binds as Dictionary).has(bone):
		return (data.binds[bone] as Transform3D).affine_inverse().origin
	return skeleton.get_bone_global_rest(bone).origin


# Per-bone thickness and far tip in bind space, measured once per mesh.
static func bone_stats(data: Dictionary, bone: int, child_joint: Variant, skeleton: Skeleton3D) -> Dictionary:
	var stats: Dictionary = data.bone_stats
	if stats.has(bone):
		return stats[bone]
	var start := joint(data, bone, skeleton)
	var points := PackedVector3Array()
	for surface: Dictionary in data.surfaces:
		var vertices: PackedVector3Array = surface.vertices
		var bones: PackedInt32Array = surface.bones
		var weights: PackedFloat32Array = surface.weights
		var stride: int = surface.stride
		if bones.is_empty():
			continue
		for index in vertices.size():
			var best := -1
			var best_weight := 0.0
			for k in stride:
				if weights[index * stride + k] > best_weight:
					best_weight = weights[index * stride + k]
					best = bones[index * stride + k]
			if best == bone:
				points.append(vertices[index])
	var finish: Vector3 = child_joint if child_joint != null else start
	if child_joint == null:
		for point in points:
			if point.distance_to(start) > finish.distance_to(start):
				finish = point
		finish = start.lerp(finish, 0.85)
	var distances: Array[float] = []
	for point in points:
		distances.append(segment_distance(point, start, finish))
	distances.sort()
	var radius := 0.05
	if not distances.is_empty():
		radius = maxf(0.025, distances[int(distances.size() * 0.6)])
	var result := {"start": start, "end": finish, "radius": radius, "count": points.size()}
	stats[bone] = result
	return result


static func segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0000001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


# Shortest distance between a ray and a segment.
static func ray_segment_distance(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3) -> float:
	var best := INF
	for step in 9:
		var point := a.lerp(b, float(step) / 8.0)
		var along := maxf(0.0, (point - origin).dot(direction))
		best = minf(best, point.distance_to(origin + direction * along))
	return best


# Wound material for one surface, copying the look of the original material.
static func wound_material(original: Material) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WOUND_SHADER
	if original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		material.set_shader_parameter("albedo_color", base.albedo_color)
		material.set_shader_parameter("roughness_value", base.roughness)
		material.set_shader_parameter("metallic_value", base.metallic)
		if base.albedo_texture != null:
			material.set_shader_parameter("albedo_texture", base.albedo_texture)
			material.set_shader_parameter("use_albedo_texture", true)
		if base.normal_enabled and base.normal_texture != null:
			material.set_shader_parameter("normal_texture", base.normal_texture)
			material.set_shader_parameter("use_normal_texture", true)
	return material


# Static mesh of the vertices that mostly follow `chain`, skinned into the
# current pose and expressed in world orientation around `center`.
# Returns {mesh, center, points} or {} when the chain owns no geometry.
static func build_piece(data: Dictionary, chain: PackedInt32Array, skeleton: Skeleton3D, materials: Array) -> Dictionary:
	var skinning := {}
	var topologies: Array[Dictionary] = []
	for i in (data.surfaces as Array).size():
		var topology := TOPOLOGY.for_surface(data, chain, i)
		topologies.append(topology)
		for bone: int in topology["bones"]:
			if not skinning.has(bone) and data.binds.has(bone):
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
		var topology: Dictionary = topologies[surface_index]
		var positions := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var rest := PackedFloat32Array()
		var out_indices: PackedInt32Array = topology["indices"]
		var source_normals: PackedVector3Array = surface.normals
		var source_uvs: PackedVector2Array = surface.uvs
		for corner: int in topology["vertices"]:
			var transform := _blend(skinning, bones, weights, stride, corner)
			positions.append(transform * vertices[corner])
			normals.append((transform.basis * (source_normals[corner] if not source_normals.is_empty() else Vector3.UP)).normalized())
			uvs.append(source_uvs[corner] if not source_uvs.is_empty() else Vector2.ZERO)
			rest.append_array([vertices[corner].x, vertices[corner].y, vertices[corner].z, 1.0])
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

