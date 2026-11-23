extends SceneTree
## Turns the costume JSON of tools/export_enemy_costumes.py into skinned game meshes.
##
##   godot --headless --path . --script res://tools/build_enemy_costumes.gd -- <json_dir> [Hunger Brute Revenant]
##
## Needs <Name>_rig.tscn and <Name>_weights.json (tools/build_enemy_rigs.gd, blender_enemy_weights.py).
## Writes into models/objects/characters/enemy/game/:
##   <Name>_<costume>_costume.res   surface 0 opaque (vertex colours), surface 1 translucent glass (hazmat visor),
##                                  skinned to the enemy's skeleton: every vertex takes the bone weights of the
##                                  nearest body vertex, so a costume bends and collapses with the body part under it
##   costume_solid.tres / costume_glass.tres   shared materials

const PARTS := preload("res://tools/enemy_rig_parts.gd")
const OUTPUT_DIR := "res://models/objects/characters/enemy/game/"
const ENEMIES := ["Hunger", "Brute", "Revenant"]
const COSTUMES := ["guard", "hazmat", "janitor", "man", "scientist"]
const LOD_KEYS := [0.012, 0.024]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: -- <json_dir> [enemy ...]")
		quit(1)
		return
	var json_dir: String = args[0]
	var only := args.slice(1)
	var solid := _material("costume_solid", false)
	var glass := _material("costume_glass", true)
	var failures := 0
	for enemy: String in ENEMIES:
		if not only.is_empty() and not only.has(enemy):
			continue
		var skeleton := _skeleton(enemy)
		var grids := _weight_grids(enemy)
		if skeleton == null or grids.is_empty():
			failures += 1
			continue
		for costume: String in COSTUMES:
			var path := "%s/%s_%s.json" % [json_dir, enemy, costume]
			if not FileAccess.file_exists(path):
				continue
			if not _build(enemy, costume, path, skeleton, grids, solid, glass):
				failures += 1
		skeleton.free()
	print("Enemy costumes built, failures: %d" % failures)
	quit(failures)


func _build(enemy: String, costume: String, path: String, skeleton: Skeleton3D, grids: Dictionary, solid: Material, glass: Material) -> bool:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var mesh := ArrayMesh.new()
	for key in ["solid", "glass"]:
		var part: Dictionary = data[key]
		if (part.indices as Array).is_empty():
			continue
		var arrays := _arrays(part, skeleton, grids)
		var lods := _lods(arrays) if key == "solid" else {}
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
		mesh.surface_set_material(mesh.get_surface_count() - 1, solid if key == "solid" else glass)
	mesh.resource_name = "%s_%s_costume" % [enemy, costume]
	var out := "%s%s_%s_costume.res" % [OUTPUT_DIR, enemy, costume]
	if ResourceSaver.save(mesh, out) != OK:
		push_error("Cannot save " + out)
		return false
	print("%s %s: %d surfaces -> %s" % [enemy, costume, mesh.get_surface_count(), out])
	return true


func _arrays(part: Dictionary, skeleton: Skeleton3D, grids: Dictionary) -> Array:
	var count: int = (part.positions as Array).size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	bones.resize(count * 4)
	weights.resize(count * 4)
	for v in count:
		var p: Array = part.positions[v]
		var n: Array = part.normals[v]
		var c: Array = part.colors[v]
		vertices[v] = Vector3(p[0], p[1], p[2])
		normals[v] = Vector3(n[0], n[1], n[2])
		colors[v] = Color(c[0], c[1], c[2], c[3])
		var row := _row(grids, vertices[v], skeleton)
		for k in 4:
			bones[v * 4 + k] = row.bones[k]
			weights[v * 4 + k] = row.weights[k]
	var indices := PackedInt32Array()
	indices.resize((part.indices as Array).size())
	for i in indices.size():
		indices[i] = int(part.indices[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


# Four strongest bones of the nearest body vertex.
func _row(grids: Dictionary, point: Vector3, skeleton: Skeleton3D) -> Dictionary:
	var nearest: int = PARTS._nearest_row(grids.cells, point)
	var picks := {}
	for k in 4:
		var weight: float = grids.weights[nearest * 4 + k]
		if weight > 0.0:
			var bone: int = skeleton.find_bone(grids.bones[int(grids.bones_of[nearest * 4 + k])])
			picks[bone] = float(picks.get(bone, 0.0)) + weight
	var bones: Array[int] = [0, 0, 0, 0]
	var weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var total := 0.0
	for bone: int in picks:
		total += float(picks[bone])
	var slot := 0
	for bone: int in picks:
		bones[slot] = bone
		weights[slot] = float(picks[bone]) / total if total > 0.0 else 0.0
		slot += 1
	if total <= 0.0:
		weights[0] = 1.0
	return {"bones": bones, "weights": weights}


func _weight_grids(enemy: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(OUTPUT_DIR + enemy + "_weights.json")
	if text.is_empty():
		push_error("Missing weights for " + enemy)
		return {}
	var data: Dictionary = JSON.parse_string(text)
	var positions: Array = data.positions
	var cells := [{}, {}]
	for v in positions.size() / 3:
		var at := Vector3(positions[v * 3], positions[v * 3 + 1], positions[v * 3 + 2])
		for level in 2:
			var cell := Vector3i((at / PARTS.LOOKUP_CELLS[level]).floor())
			if not cells[level].has(cell):
				cells[level][cell] = []
			cells[level][cell].append([at, v])
	return {"cells": cells, "bones": data.bones, "bones_of": data.bones_of, "weights": data.weights}


func _skeleton(enemy: String) -> Skeleton3D:
	var scene := load(OUTPUT_DIR + enemy + "_rig.tscn") as PackedScene
	if scene == null:
		push_error("Missing rig for " + enemy)
		return null
	var visual := scene.instantiate()
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	visual.remove_child(skeleton)
	visual.free()
	return skeleton


func _lods(arrays: Array) -> Dictionary:
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(25.0, 60.0, [])
	var result := {}
	var previous: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	for lod in mini(importer.get_surface_lod_count(0), LOD_KEYS.size()):
		var indices := importer.get_surface_lod_indices(0, lod)
		if indices.size() >= previous:
			break
		result[LOD_KEYS[lod]] = indices
		previous = indices.size()
	return result


func _material(file: String, translucent: bool) -> Material:
	var path := OUTPUT_DIR + file + ".tres"
	if ResourceLoader.exists(path):
		return load(path)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.82
	if translucent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.19
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ResourceSaver.save(material, path)
	return load(path)
