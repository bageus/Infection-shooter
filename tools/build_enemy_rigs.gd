extends SceneTree
## Auto-rigs the static enemy game meshes and bakes enemy animation clips.
##
## Run after tools/build_enemy_game_models.gd and an editor import:
##   godot --headless --path . --script res://tools/build_enemy_rigs.gd
##
## For the five humanoids and the Horde it writes into models/objects/characters/enemy/game/:
##   <Name>_rig_mesh.res  skinned copy of <Name>_game.res (skin + cut caps, 4 weights/vertex)
##   <Name>_anims.res     AnimationLibrary (Idle, Walk, Run, attacks, Death, extras)
##   <Name>_rig.tscn      Visual > Skeleton3D > Mesh + AnimationPlayer

const AUTHOR := preload("res://tools/enemy_animation_author.gd")
const HORDE_AUTHOR := preload("res://tools/horde_animation_author.gd")
const OUTPUT_DIR := "res://models/objects/characters/enemy/game/"
const PARTS := preload("res://tools/enemy_rig_parts.gd")
const HUMANOID_BONES := [
	["Root", ""], ["Hips", "Root"], ["Spine", "Hips"], ["Chest", "Spine"], ["Neck", "Chest"], ["Head", "Neck"],
	["L_Shoulder", "Chest"], ["L_UpperArm", "L_Shoulder"], ["L_Forearm", "L_UpperArm"], ["L_Hand", "L_Forearm"],
	["R_Shoulder", "Chest"], ["R_UpperArm", "R_Shoulder"], ["R_Forearm", "R_UpperArm"], ["R_Hand", "R_Forearm"],
	["L_Thigh", "Hips"], ["L_Shin", "L_Thigh"], ["L_Foot", "L_Shin"], ["L_Toe", "L_Foot"],
	["R_Thigh", "Hips"], ["R_Shin", "R_Thigh"], ["R_Foot", "R_Shin"], ["R_Toe", "R_Foot"],
]
# Per enemy clip style; speeds are derived from stride and printed for scenes.
# Per enemy clip style. walk_mps/run_mps are the gameplay speeds (metres per
# second, world units) the clips are paced for; scale is the Body scale.
const STYLES := {
	"Hunger": {"scale": 1.0, "walk_mps": 2.16, "run_mps": 5.4, "walk_swing": 28.0, "run_swing": 40.0, "lean": 30.0, "reach": 1.0, "heavy": 0.0, "attack_seconds": 0.9, "death_seconds": 1.5},
	"Revenant": {"scale": 1.0, "walk_mps": 1.84, "run_mps": 4.6, "walk_swing": 27.0, "run_swing": 38.0, "lean": 26.0, "reach": 0.8, "heavy": 0.1, "attack_seconds": 1.0, "death_seconds": 1.6},
	"Brute": {"scale": 1.1, "walk_mps": 1.64, "run_mps": 4.1, "walk_swing": 26.0, "run_swing": 36.0, "lean": 24.0, "reach": 0.6, "heavy": 0.35, "attack_seconds": 1.1, "death_seconds": 1.7},
	"Titan": {"scale": 1.35, "walk_mps": 1.32, "run_mps": 3.3, "walk_swing": 24.0, "run_swing": 32.0, "lean": 20.0, "reach": 0.4, "heavy": 0.7, "attack_seconds": 1.3, "death_seconds": 2.0, "throw": true, "throw_seconds": 1.7},
	"Colossus": {"scale": 1.55, "walk_mps": 1.16, "run_mps": 2.9, "walk_swing": 22.0, "run_swing": 30.0, "lean": 18.0, "reach": 0.3, "heavy": 1.0, "attack_seconds": 1.4, "death_seconds": 2.2, "slam": true, "slam_seconds": 1.7},
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := 0
	for enemy_name: String in STYLES:
		if not _build_humanoid(enemy_name):
			failures += 1
	if not _build_horde():
		failures += 1
	print("Enemy rigs built, failures: %d" % failures)
	quit(failures)


# ---------------------------------------------------------------- humanoids

# Joints come from the cut ends of the source parts (tools/enemy_rig_parts.gd),
# skin weights keep every part on its own bones with a soft blend across each joint.
func _build_humanoid(enemy_name: String) -> bool:
	var model := PARTS.load_model(OUTPUT_DIR, enemy_name)
	if model == null:
		push_error("Missing game mesh for " + enemy_name)
		return false
	var points: Dictionary = PARTS.humanoid_joints(model)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for entry: Array in HUMANOID_BONES:
		var index := skeleton.add_bone(entry[0])
		var parent: String = entry[1]
		var origin: Vector3 = points[entry[0]]
		if not parent.is_empty():
			skeleton.set_bone_parent(index, skeleton.find_bone(parent))
			origin -= points[parent] as Vector3
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, origin))
	skeleton.reset_bone_poses()
	var weights: Array = PARTS.humanoid_weights(model, points, skeleton)
	var author := AUTHOR.new()
	author.setup(skeleton)
	var style: Dictionary = STYLES[enemy_name]
	var library: AnimationLibrary = author.build_humanoid_library(style)
	print("%s: pace %s, hips %.2f, leg %.2f" % [enemy_name, author.pace(style), author.hips_height, author.leg_length])
	return _save_rig(enemy_name, skeleton, model.surfaces, weights, library)


# ---------------------------------------------------------------- shared output

func _save_rig(enemy_name: String, skeleton: Skeleton3D, surfaces: Array, dense_per_surface: Array, library: AnimationLibrary) -> bool:
	var game := load(OUTPUT_DIR + enemy_name + "_game.res") as ArrayMesh
	var mesh := ArrayMesh.new()
	var vertex_total := 0
	for surface_index in surfaces.size():
		var skinned := _skin_surface(surfaces[surface_index], dense_per_surface[surface_index])
		vertex_total += (skinned[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		# Same vertices as the game mesh, so its LOD index lists carry over.
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, skinned, [], _stored_lods(game, surface_index))
	return _write_rig(enemy_name, skeleton, mesh, vertex_total, library)


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


# Four strongest bones per vertex; the part id stored in COLOR is dropped.
func _skin_surface(arrays: Array, dense: Array) -> Array:
	var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(count * 4)
	weights.resize(count * 4)
	for v in count:
		var row: PackedFloat32Array = dense[v]
		var picks := []
		for b in row.size():
			if row[b] > 0.0:
				picks.append([row[b], b])
		picks.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
		picks = picks.slice(0, 4)
		var total := 0.0
		for pick: Array in picks:
			total += float(pick[0])
		for k in 4:
			if k < picks.size() and total > 0.0 and float(picks[k][0]) / total >= 0.02:
				bones[v * 4 + k] = int(picks[k][1])
				weights[v * 4 + k] = float(picks[k][0]) / total
		var kept := 0.0
		for k in 4:
			kept += weights[v * 4 + k]
		if kept <= 0.0:
			bones[v * 4] = 1
			weights[v * 4] = 1.0
		else:
			for k in 4:
				weights[v * 4 + k] /= kept
	var skinned := arrays.duplicate()
	skinned[Mesh.ARRAY_COLOR] = null
	skinned[Mesh.ARRAY_BONES] = bones
	skinned[Mesh.ARRAY_WEIGHTS] = weights
	return skinned


func _write_rig(enemy_name: String, skeleton: Skeleton3D, mesh: ArrayMesh, count: int, library: AnimationLibrary) -> bool:
	mesh.resource_name = enemy_name + "_rig"
	var mesh_path := OUTPUT_DIR + enemy_name + "_rig_mesh.res"
	var library_path := OUTPUT_DIR + enemy_name + "_anims.res"
	if ResourceSaver.save(mesh, mesh_path) != OK or ResourceSaver.save(library, library_path) != OK:
		push_error("Cannot save rig resources for " + enemy_name)
		return false
	var skin := Skin.new()
	for index in skeleton.get_bone_count():
		skin.add_bind(index, skeleton.get_bone_global_rest(index).affine_inverse())
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.add_child(skeleton)
	skeleton.owner = visual
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = load(mesh_path)
	mesh_instance.skin = skin
	mesh_instance.skeleton = NodePath("..")
	for surface in 2:
		var material := load(OUTPUT_DIR + enemy_name + ("_game.tres" if surface == 0 else "_wound.tres")) as Material
		if material != null and surface < mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)
	skeleton.add_child(mesh_instance)
	mesh_instance.owner = visual
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library(&"", load(library_path))
	visual.add_child(player)
	player.owner = visual
	var packed := PackedScene.new()
	packed.pack(visual)
	var scene_path := OUTPUT_DIR + enemy_name + "_rig.tscn"
	var error := ResourceSaver.save(packed, scene_path)
	visual.free()
	if error != OK:
		push_error("Cannot save %s: %d" % [scene_path, error])
		return false
	print("%s rig: %d bones, %d vertices -> %s" % [enemy_name, skin.get_bind_count(), count, scene_path])
	return true


# ---------------------------------------------------------------- horde

func _build_horde() -> bool:
	var model := PARTS.load_model(OUTPUT_DIR, "Horde")
	if model == null:
		return false
	var author := HORDE_AUTHOR.new()
	var legs: Dictionary = PARTS.horde_legs(model)
	author.leg_angles = legs.angles
	author.leg_joints = legs.joints
	var skeleton: Skeleton3D = author.build_skeleton(model.vertices(0))
	var weights: Array = PARTS.horde_weights(model, author, skeleton, legs)
	var library: AnimationLibrary = author.build_library(skeleton)
	print("Horde: crawl %.2f m/s, ram %.2f m/s" % [author.crawl_speed(), author.ram_speed()])
	return _save_rig("Horde", skeleton, model.surfaces, weights, library)
