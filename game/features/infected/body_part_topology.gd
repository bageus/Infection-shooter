extends RefCounted
## Immutable part membership, unique vertex order, remapped indices and bones.
## Lives in the existing prepared-mesh data cache; no posed vertices are kept.
const CHAIN_MEMBERSHIP := .5

static func for_surface(data: Dictionary, chain: PackedInt32Array, surface_index: int) -> Dictionary:
	var cache: Dictionary = data.get_or_add("piece_topology", {})
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
	if not bones.is_empty():
		for index in vertices.size():
			var share := 0.0
			for k in stride:
				if chain.has(bones[index * stride + k]):
					share += weights[index * stride + k]
			member[index] = 1 if share >= CHAIN_MEMBERSHIP else 0
	var unique := PackedInt32Array()
	var remapped := PackedInt32Array()
	var index_map: Dictionary = {}
	var used_bones: Dictionary = {}
	var source_indices: PackedInt32Array = surface.indices
	for t in range(0, source_indices.size(), 3):
		if member[source_indices[t]] == 0 or member[source_indices[t + 1]] == 0 or member[source_indices[t + 2]] == 0:
			continue
		for offset in 3:
			var corner := source_indices[t + offset]
			if not index_map.has(corner):
				index_map[corner] = unique.size()
				unique.append(corner)
				for k in stride:
					if weights[corner * stride + k] > 0:
						used_bones[bones[corner * stride + k]] = true
			remapped.append(index_map[corner])
	var result := {"vertices": unique, "indices": remapped, "bones": PackedInt32Array(used_bones.keys())}
	cache[key] = result
	return result
