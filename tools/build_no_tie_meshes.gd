extends SceneTree
## Writes <Enemy>_rig_mesh_no_tie.res: the rig mesh without the necktie triangles, for the "no_tie" skin.
##
##   godot --headless --path . --script res://tools/build_no_tie_meshes.gd -- <mask_dir>
##
## Needs <mask_dir>/<Enemy>_tie_mask.png (tools/find_enemy_tie.py). Triangles whose UV centre lies on
## a white mask pixel are the tie; they leave the base index list and every LOD list.
const DIR := "res://models/objects/characters/enemy/game/"
const ENEMIES := ["Hunger", "Brute", "Revenant"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: -- <mask_dir>")
		quit(1)
		return
	var failures := 0
	for enemy: String in ENEMIES:
		if not _build(enemy, args[0]):
			failures += 1
	quit(failures)


func _build(enemy: String, mask_dir: String) -> bool:
	var mask := Image.load_from_file("%s/%s_tie_mask.png" % [mask_dir, enemy])
	var source := load("%s%s_rig_mesh.res" % [DIR, enemy]) as ArrayMesh
	if mask == null or source == null:
		push_error("Missing inputs for " + enemy)
		return false
	var mesh := ArrayMesh.new()
	var removed := 0
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var lods := _stored_lods(source, surface)
		var base := _without_tie(arrays[Mesh.ARRAY_INDEX], uvs, mask)
		removed += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() - base.size()
		arrays[Mesh.ARRAY_INDEX] = base
		for edge in lods:
			lods[edge] = _without_tie(lods[edge], uvs, mask)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	mesh.resource_name = enemy + "_rig_mesh_no_tie"
	print("%s: %d tie triangles removed" % [enemy, removed / 3])
	return ResourceSaver.save(mesh, "%s%s_rig_mesh_no_tie.res" % [DIR, enemy]) == OK


func _without_tie(indices: PackedInt32Array, uvs: PackedVector2Array, mask: Image) -> PackedInt32Array:
	var kept := PackedInt32Array()
	for t in indices.size() / 3:
		var uv := (uvs[indices[t * 3]] + uvs[indices[t * 3 + 1]] + uvs[indices[t * 3 + 2]]) / 3.0
		var at := Vector2i(clampi(int(uv.x * mask.get_width()), 0, mask.get_width() - 1), clampi(int(uv.y * mask.get_height()), 0, mask.get_height() - 1))
		if mask.get_pixelv(at).r < 0.5:
			kept.append_array(indices.slice(t * 3, t * 3 + 3))
	return kept


static func _stored_lods(mesh: ArrayMesh, surface: int) -> Dictionary:
	var stored := RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
	var stride := RenderingServer.mesh_surface_get_format_index_stride(stored.format, stored.vertex_count)
	var result := {}
	for lod: Dictionary in stored.get("lods", []):
		var bytes: PackedByteArray = lod.index_data
		var indices := PackedInt32Array()
		indices.resize(bytes.size() / stride)
		for index in indices.size():
			indices[index] = bytes.decode_u16(index * stride) if stride == 2 else bytes.decode_u32(index * stride)
		result[float(lod.edge_length)] = indices
	return result
