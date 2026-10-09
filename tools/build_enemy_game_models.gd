extends SceneTree
## Builds lightweight game-ready copies of the heavy enemy source GLBs.
##
## Run after the project has been imported once:
##   godot --headless --path . --script res://tools/build_enemy_game_models.gd
##
## Source files are never modified. For every enemy it writes into
## models/objects/characters/enemy/game/:
##   <Name>_game.res         compacted mesh (Godot meshopt LOD, one surface)
##   <Name>_albedo.jpg       base colour, downscaled
##   <Name>_normal.jpg       normal map, downscaled
##   <Name>_game.tres        StandardMaterial3D using the two textures
## Tune TARGET_INDICES / TEXTURE_SIZE here and re-run to regenerate.

const SOURCE_DIR := "res://models/objects/characters/enemy/"
const OUTPUT_DIR := "res://models/objects/characters/enemy/game/"
const NAMES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus", "Horde"]
const TARGET_INDICES := 27000 # about 9k triangles per enemy
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
	var mesh_instance := _find_mesh(instance)
	if mesh_instance == null or not mesh_instance.mesh is ArrayMesh:
		push_error("Source has no ArrayMesh: " + enemy_name)
		instance.free()
		return false
	var source_mesh := mesh_instance.mesh as ArrayMesh
	var arrays := source_mesh.surface_get_arrays(0)
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, enemy_name)
	importer.generate_lods(25.0, 60.0, [])
	var chosen := _choose_lod(importer)
	var indices: PackedInt32Array = importer.get_surface_lod_indices(0, chosen) if chosen >= 0 else arrays[Mesh.ARRAY_INDEX]
	var compact := _compact(arrays, indices)
	var lod_builder := ImporterMesh.new()
	lod_builder.add_surface(Mesh.PRIMITIVE_TRIANGLES, compact)
	lod_builder.generate_lods(25.0, 60.0, [])
	var mesh := lod_builder.get_mesh()
	mesh.resource_name = enemy_name + "_game"
	var mesh_path := OUTPUT_DIR + enemy_name + "_game.res"
	var error := ResourceSaver.save(mesh, mesh_path)
	if error != OK:
		push_error("Cannot save %s: %d" % [mesh_path, error])
		instance.free()
		return false
	var bounds := mesh.get_aabb()
	@warning_ignore("integer_division")
	var triangles := (compact[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("%s: lod %d -> %d triangles, %d vertices, aabb %s" % [enemy_name, chosen, triangles, (compact[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), bounds])
	var ok := _write_texture(enemy_name, 0, "albedo") and _write_texture(enemy_name, 2, "normal")
	_write_material(enemy_name)
	instance.free()
	return ok


func _choose_lod(importer: ImporterMesh) -> int:
	for lod in importer.get_surface_lod_count(0):
		if importer.get_surface_lod_indices(0, lod).size() <= TARGET_INDICES:
			return lod
	return importer.get_surface_lod_count(0) - 1


# Re-index the vertex streams so only vertices used by the chosen LOD remain.
func _compact(arrays: Array, indices: PackedInt32Array) -> Array:
	var index_remap := {}
	var order := PackedInt32Array()
	var new_indices := PackedInt32Array()
	new_indices.resize(indices.size())
	for i in indices.size():
		var old := indices[i]
		var mapped: int = index_remap.get(old, -1)
		if mapped < 0:
			mapped = order.size()
			index_remap[old] = mapped
			order.append(old)
		new_indices[i] = mapped
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var new_vertices := PackedVector3Array()
	var new_normals := PackedVector3Array()
	var new_uvs := PackedVector2Array()
	var new_tangents := PackedFloat32Array()
	new_vertices.resize(order.size())
	new_normals.resize(order.size())
	new_uvs.resize(order.size())
	if not tangents.is_empty():
		new_tangents.resize(order.size() * 4)
	for n in order.size():
		var old := order[n]
		new_vertices[n] = vertices[old]
		new_normals[n] = normals[old]
		new_uvs[n] = uvs[old]
		if not tangents.is_empty():
			for c in 4:
				new_tangents[n * 4 + c] = tangents[old * 4 + c]
	result[Mesh.ARRAY_VERTEX] = new_vertices
	result[Mesh.ARRAY_NORMAL] = new_normals
	result[Mesh.ARRAY_TEX_UV] = new_uvs
	if not new_tangents.is_empty():
		result[Mesh.ARRAY_TANGENT] = new_tangents
	result[Mesh.ARRAY_INDEX] = new_indices
	return result


func _write_texture(enemy_name: String, source_index: int, suffix: String) -> bool:
	var source := ProjectSettings.globalize_path("%s%s_%d.jpg" % [SOURCE_DIR, enemy_name, source_index])
	var image := Image.load_from_file(source)
	if image == null or image.is_empty():
		push_error("Cannot read texture " + source)
		return false
	image.resize(TEXTURE_SIZE, TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
	var target := ProjectSettings.globalize_path("%s%s_%s.jpg" % [OUTPUT_DIR, enemy_name, suffix])
	return image.save_jpg(target, JPG_QUALITY) == OK


func _write_material(enemy_name: String) -> void:
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
	var file := FileAccess.open(OUTPUT_DIR + enemy_name + "_game.tres", FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
