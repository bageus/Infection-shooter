extends SceneTree
## Builds game-ready meshes and textures from the enemy source GLBs.
##
## Run after the project has been imported once:
##   godot --headless --path . --script res://tools/build_enemy_game_models.gd
##
## A source GLB holds one closed, rig-less mesh per body part (head, torso,
## upper arm, forearm+hand, thigh, shin+foot, Horde body and legs). Each part has
## two surfaces: skin and the wound tissue of its cut ends ("caps"). Source files
## are never modified. For every enemy it writes into models/objects/characters/enemy/game/:
##   <Name>_game.res    all parts merged: surface 0 skin, surface 1 cut caps;
##                      vertex COLOR.r * PART_ID_SCALE is the part id
##   <Name>_parts.json  part ids and the cut caps of every part (rig joints come from them)
##   <Name>_albedo.jpg / <Name>_normal.jpg / <Name>_wound.jpg   downscaled textures
##   <Name>_game.tres / <Name>_wound.tres   materials (only written when missing)

const SOURCE_DIR := "res://models/objects/characters/enemy/"
const OUTPUT_DIR := "res://models/objects/characters/enemy/game/"
const NAMES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus", "Horde"]
const PART_ID_SCALE := 32.0
# Crowd budget (run_enemy_animation_tests): about 9k triangles of skin per enemy plus the cut caps.
# Part budgets follow triangles^0.8, so small parts (heads, hands) keep more of their detail.
const SKIN_TRIANGLES := 9000
const CAP_TRIANGLES := 1000
const TEXTURE_SIZE := 1024
const JPG_QUALITY := 0.9


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var failures := 0
	for enemy_name: String in NAMES:
		if not _build(enemy_name):
			failures += 1
	print("Enemy game models built, failures: %d" % failures)
	quit(failures)


func _build(enemy_name: String) -> bool:
	var scene := load(SOURCE_DIR + enemy_name + ".glb") as PackedScene
	if scene == null:
		push_error("Missing source model: " + enemy_name)
		return false
	var instance := scene.instantiate()
	var nodes: Array = []
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh is ArrayMesh and mesh_instance.mesh.get_surface_count() == 2:
			nodes.append(mesh_instance)
	nodes.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	if nodes.is_empty():
		push_error("Source has no two-surface part meshes: " + enemy_name)
		instance.free()
		return false
	var merged := [_new_surface(), _new_surface()]
	var parts: Array = []
	var shares := [0.0, 0.0]
	for node: MeshInstance3D in nodes:
		for surface in 2:
			shares[surface] += pow(float(node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size() / 3), 0.8)
	for id in nodes.size():
		var node := nodes[id] as MeshInstance3D
		var transform := _relative(node, instance)
		for surface in 2:
			var arrays := node.mesh.surface_get_arrays(surface)
			var budget: float = (SKIN_TRIANGLES if surface == 0 else CAP_TRIANGLES) * pow(float(arrays[Mesh.ARRAY_INDEX].size() / 3), 0.8) / shares[surface]
			var simplified := _simplify(arrays, maxi(int(budget), 12))
			_append(merged[surface], simplified, transform, id, _part_lods(simplified))
		parts.append({"name": String(node.name), "id": id, "caps": _caps(node.mesh.surface_get_arrays(1), transform)})
	var mesh := ArrayMesh.new()
	for surface in 2:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _finish(merged[surface]), [], _lods(merged[surface], surface))
	mesh.resource_name = enemy_name + "_game"
	var mesh_path := OUTPUT_DIR + enemy_name + "_game.res"
	if ResourceSaver.save(mesh, mesh_path) != OK:
		push_error("Cannot save " + mesh_path)
		instance.free()
		return false
	var file := FileAccess.open(OUTPUT_DIR + enemy_name + "_parts.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"parts": parts}, "  "))
	file.close()
	@warning_ignore("integer_division")
	var triangles := (merged[0].indices as PackedInt32Array).size() / 3 + (merged[1].indices as PackedInt32Array).size() / 3
	print("%s: %d parts, %d triangles, aabb %s" % [enemy_name, parts.size(), triangles, mesh.get_aabb()])
	instance.free()
	var ok := _write_textures(enemy_name)
	_write_material(enemy_name)
	_write_wound_material(enemy_name)
	return ok


static func _relative(node: Node3D, root: Node) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform


# The meshopt LOD of the part whose triangle count is closest to `target` (the full part
# when it already fits), re-indexed to its own vertices.
static func _simplify(arrays: Array, target: int) -> Array:
	# One pass reaches only so far; repeat while the part is clearly above its budget.
	for pass_index in 4:
		var count: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		if count <= target * 1.15:
			break
		var next := _simplify_once(arrays, target)
		if (next[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 >= count:
			break
		arrays = next
	return arrays


static func _simplify_once(arrays: Array, target: int) -> Array:
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if full.size() / 3 <= target:
		return arrays
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(60.0, 90.0, [])
	var chosen := full
	var best := absf(log(float(full.size() / 3) / float(target)))
	for lod in importer.get_surface_lod_count(0):
		var indices := importer.get_surface_lod_indices(0, lod)
		var distance := absf(log(maxf(float(indices.size() / 3), 1.0) / float(target)))
		if distance < best:
			best = distance
			chosen = indices
	return _compact(arrays, chosen)


static func _compact(arrays: Array, indices: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var new_indices := PackedInt32Array()
	for old in indices:
		if not remap.has(old):
			remap[old] = order.size()
			order.append(old)
		new_indices.append(remap[old])
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	var new_vertices := PackedVector3Array()
	var new_normals := PackedVector3Array()
	var new_uvs := PackedVector2Array()
	var new_tangents := PackedFloat32Array()
	for old in order:
		new_vertices.append(vertices[old])
		new_normals.append(normals[old])
		new_uvs.append(uvs[old])
		new_tangents.append_array(tangents.slice(old * 4, old * 4 + 4))
	result[Mesh.ARRAY_VERTEX] = new_vertices
	result[Mesh.ARRAY_NORMAL] = new_normals
	result[Mesh.ARRAY_TEX_UV] = new_uvs
	result[Mesh.ARRAY_TANGENT] = new_tangents
	result[Mesh.ARRAY_INDEX] = new_indices
	return result


static func _new_surface() -> Dictionary:
	return {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(),
		"tangents": PackedFloat32Array(), "colors": PackedColorArray(), "indices": PackedInt32Array(),
		"lod_near": PackedInt32Array(), "lod_far": PackedInt32Array()}


static func _append(target: Dictionary, arrays: Array, transform: Transform3D, part_id: int, lods: Array) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var out_vertices: PackedVector3Array = target.vertices
	var out_normals: PackedVector3Array = target.normals
	var out_uvs: PackedVector2Array = target.uvs
	var out_tangents: PackedFloat32Array = target.tangents
	var out_colors: PackedColorArray = target.colors
	var out_indices: PackedInt32Array = target.indices
	var near: PackedInt32Array = target.lod_near
	var far: PackedInt32Array = target.lod_far
	var base := out_vertices.size()
	var color := Color(float(part_id) / PART_ID_SCALE, 0.0, 0.0, 1.0)
	for index in vertices.size():
		out_vertices.append(transform * vertices[index])
		out_normals.append((transform.basis * normals[index]).normalized())
		out_uvs.append(uvs[index])
		var tangent := transform.basis * Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])
		out_tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, tangents[index * 4 + 3]]))
		out_colors.append(color)
	for index: int in arrays[Mesh.ARRAY_INDEX]:
		out_indices.append(base + index)
	for index: int in lods[0]:
		near.append(base + index)
	for index: int in lods[1]:
		far.append(base + index)
	target.lod_near = near
	target.lod_far = far
	target.vertices = out_vertices
	target.normals = out_normals
	target.uvs = out_uvs
	target.tangents = out_tangents
	target.colors = out_colors
	target.indices = out_indices


# Index lists of a coarser and a much coarser version of one part (about 50% and 25% of its
# triangles) over the part's own vertices; a part that cannot be reduced keeps its full indices.
static func _part_lods(arrays: Array) -> Array:
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var near := _reduce(arrays, full, full.size() / 6)
	return [near, _reduce(arrays, near, full.size() / 12)]


# Repeats meshopt passes over the same vertices (unused ones stay in place) until at most
# `target` triangles are left, or a pass stops helping.
static func _reduce(arrays: Array, indices: PackedInt32Array, target: int) -> PackedInt32Array:
	for pass_index in 5:
		if indices.size() / 3 <= target * 1.15:
			break
		var step := arrays.duplicate()
		step[Mesh.ARRAY_INDEX] = indices
		var tool := SurfaceTool.new()
		tool.create_from_arrays(step)
		var best := tool.generate_lod(1.0, maxi(target * 3, 3))
		if best.size() >= indices.size():
			break
		indices = best
	if indices.size() / 3 > target * 1.15:
		indices = _cluster(arrays, indices, target)
	return indices


# Last resort for meshes meshopt leaves alone: vertex clustering on a grid, keeping one real
# vertex per cell so the result still indexes the same buffer. Cells grow until it fits.
static func _cluster(arrays: Array, indices: PackedInt32Array, target: int) -> PackedInt32Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cell := 0.004
	var result := indices
	for step in 12:
		var representative := {}
		var kept := PackedInt32Array()
		for triangle in indices.size() / 3:
			var mapped := []
			for corner in 3:
				var vertex: int = indices[triangle * 3 + corner]
				var key := Vector3i((vertices[vertex] / cell).floor())
				if not representative.has(key):
					representative[key] = vertex
				mapped.append(representative[key])
			if mapped[0] != mapped[1] and mapped[1] != mapped[2] and mapped[0] != mapped[2]:
				kept.append_array(PackedInt32Array(mapped))
		result = kept
		if kept.size() / 3 <= target:
			break
		cell *= 1.5
	return result


# Screen-size thresholds (edge_length) of the two LOD levels, as the old baked meshes used them.
static func _lods(surface: Dictionary, index: int) -> Dictionary:
	var full: PackedInt32Array = surface.indices
	var near: PackedInt32Array = surface.lod_near
	var far: PackedInt32Array = surface.lod_far
	if near.size() >= full.size():
		near = _whole_lod(surface, full, full.size() / 6)
	if far.size() >= near.size():
		far = _whole_lod(surface, near, near.size() / 6)
	var result := {}
	if near.size() < full.size():
		result[1.2 if index == 0 else 0.13] = near
	if far.size() < near.size():
		result[1.8 if index == 0 else 0.2] = far
	return result


# Parts meshopt could not reduce one by one are reduced across the whole merged surface.
static func _whole_lod(surface: Dictionary, indices: PackedInt32Array, target: int) -> PackedInt32Array:
	var arrays := _finish(surface)
	arrays[Mesh.ARRAY_INDEX] = indices
	return _reduce(arrays, indices, target)


static func _finish(surface: Dictionary) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = surface.vertices
	arrays[Mesh.ARRAY_NORMAL] = surface.normals
	arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
	arrays[Mesh.ARRAY_TANGENT] = surface.tangents
	arrays[Mesh.ARRAY_COLOR] = surface.colors
	arrays[Mesh.ARRAY_INDEX] = surface.indices
	return arrays


# One entry per connected patch of cap triangles (a cut end): centre, radius
# (mean distance of its vertices from the centre) and triangle count.
static func _caps(arrays: Array, transform: Transform3D) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var weld := {}
	var canonical := PackedInt32Array()
	canonical.resize(vertices.size())
	for v in vertices.size():
		var key := Vector3i(roundi(vertices[v].x * 10000.0), roundi(vertices[v].y * 10000.0), roundi(vertices[v].z * 10000.0))
		if not weld.has(key):
			weld[key] = v
		canonical[v] = int(weld[key])
	var parent := {}
	for t in range(0, indices.size(), 3):
		var a := _find(parent, canonical[indices[t]])
		for k in [1, 2]:
			var b := _find(parent, canonical[indices[t + k]])
			if a != b:
				parent[b] = a
	var patches := {}
	for t in range(0, indices.size(), 3):
		var root := _find(parent, canonical[indices[t]])
		if not patches.has(root):
			patches[root] = {"points": PackedVector3Array(), "triangles": 0}
		patches[root].triangles += 1
		var patch_points: PackedVector3Array = patches[root].points
		for k in 3:
			patch_points.append(transform * vertices[indices[t + k]])
		patches[root].points = patch_points
	var result: Array = []
	for root: int in patches:
		var points: PackedVector3Array = patches[root].points
		var center := Vector3.ZERO
		for point in points:
			center += point
		center /= float(points.size())
		var radius := 0.0
		for point in points:
			radius += point.distance_to(center)
		radius /= float(points.size())
		result.append({"center": [center.x, center.y, center.z], "radius": radius, "triangles": patches[root].triangles})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.triangles) > int(b.triangles))
	return result


static func _find(parent: Dictionary, node: int) -> int:
	var root := node
	while parent.has(root):
		root = parent[root]
	while parent.has(node) and parent[node] != root:
		var next: int = parent[node]
		parent[node] = root
		node = next
	return root


# Reads the GLB's embedded images straight from its binary chunk.
func _write_textures(enemy_name: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(SOURCE_DIR + enemy_name + ".glb")
	if bytes.size() < 20:
		push_error("Cannot read " + enemy_name + ".glb")
		return false
	var json_length := bytes.decode_u32(12)
	var document: Dictionary = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	var bin_start := 20 + json_length + 8
	var materials: Array = document.materials
	var body_material: Dictionary = materials[0]
	var wound_material: Dictionary = materials[materials.size() - 1]
	var wanted := {
		"albedo": int(body_material.pbrMetallicRoughness.baseColorTexture.index),
		"normal": int(body_material.normalTexture.index),
		"wound": int(wound_material.pbrMetallicRoughness.baseColorTexture.index),
	}
	var ok := true
	for suffix: String in wanted:
		var texture: Dictionary = document.textures[wanted[suffix]]
		var image_info: Dictionary = document.images[int(texture.source)]
		var view: Dictionary = document.bufferViews[int(image_info.bufferView)]
		var start := bin_start + int(view.get("byteOffset", 0))
		var data := bytes.slice(start, start + int(view.byteLength))
		var image := Image.new()
		var error := image.load_jpg_from_buffer(data) if str(image_info.mimeType) == "image/jpeg" else image.load_png_from_buffer(data)
		if error != OK:
			push_error("Cannot decode %s texture of %s" % [suffix, enemy_name])
			ok = false
			continue
		image.resize(mini(image.get_width(), TEXTURE_SIZE), mini(image.get_height(), TEXTURE_SIZE), Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGB8)
		var target := ProjectSettings.globalize_path("%s%s_%s.jpg" % [OUTPUT_DIR, enemy_name, suffix])
		ok = image.save_jpg(target, JPG_QUALITY) == OK and ok
	return ok


func _write_material(enemy_name: String) -> void:
	# Keep existing material tuning (glow colour, energy) as set by the glow pass; only write a missing file.
	if FileAccess.file_exists(OUTPUT_DIR + enemy_name + "_game.tres"):
		return
	var text := """[gd_resource type="StandardMaterial3D" load_steps=3 format=3]

[ext_resource type="Texture2D" path="%s%s_albedo.jpg" id="1_albedo"]
[ext_resource type="Texture2D" path="%s%s_normal.jpg" id="2_normal"]

[resource]
resource_name = "%s_game"
cull_mode = 2
albedo_texture = ExtResource("1_albedo")
roughness = 0.8
normal_enabled = true
normal_texture = ExtResource("2_normal")
""" % [OUTPUT_DIR, enemy_name, OUTPUT_DIR, enemy_name, enemy_name]
	_store(OUTPUT_DIR + enemy_name + "_game.tres", text)


# Wet cut tissue of the part ends, visible where a neighbouring part is shot off.
func _write_wound_material(enemy_name: String) -> void:
	if FileAccess.file_exists(OUTPUT_DIR + enemy_name + "_wound.tres"):
		return
	var text := """[gd_resource type="StandardMaterial3D" load_steps=2 format=3]

[ext_resource type="Texture2D" path="%s%s_wound.jpg" id="1_wound"]

[resource]
resource_name = "%s_wound"
cull_mode = 2
albedo_texture = ExtResource("1_wound")
roughness = 0.33
clearcoat_enabled = true
clearcoat = 0.15
""" % [OUTPUT_DIR, enemy_name, enemy_name]
	_store(OUTPUT_DIR + enemy_name + "_wound.tres", text)


func _store(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
