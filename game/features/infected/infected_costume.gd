extends RefCounted
## Costume skin of an infected (Hunger, Brute, Revenant): one extra skinned mesh over the body.
##
## The skin comes from the actor's meta `skin` (spawn order, see SpawnConfig.SKINS). The costume mesh
## is built by tools/build_enemy_costumes.gd with the bone weights of the body under it, so it bends
## with the body and collapses with a severed part. Costumes are not part of the wound/blood skin:
## body_parts.gd skips the instance through the `body_part_cap` meta.
const DIR := "res://models/objects/characters/enemy/game/"
## Skin id to the costume mesh it wears; "normal" shows the body as it is. "no_tie" wears the shirt
## placket overlay ("man") until the artist says how it should differ from the normal suit.
const COSTUMES := {
	&"no_tie": "man",
	&"janitor": "janitor",
	&"guard": "guard",
	&"scientist": "scientist",
	&"hazmat": "hazmat",
}
const NODE_NAME := "Costume"
const MESH := preload("res://game/features/infected/body_part_mesh.gd")


## Adds the costume of `skin` under the skeleton of `visual_root`; returns it or null.
static func apply(visual_root: Node3D, skin: StringName) -> MeshInstance3D:
	if visual_root == null or not COSTUMES.has(skin):
		return null
	var skeleton := visual_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.has_node(NODE_NAME):
		return null
	var body := _body_mesh(skeleton)
	var enemy := _enemy_name(visual_root)
	var path := "%s%s_%s_costume.res" % [DIR, enemy, COSTUMES[skin]]
	if body == null or enemy.is_empty() or not ResourceLoader.exists(path):
		return null
	var costume := MeshInstance3D.new()
	costume.name = NODE_NAME
	costume.mesh = load(path)
	costume.skin = body.skin
	costume.skeleton = NodePath("..")
	costume.set_meta(&"body_part_cap", true)
	costume.set_meta(&"skin", skin)
	skeleton.add_child(costume)
	return costume


## Enemy name of a rig scene ("Hunger" for Hunger_rig.tscn), from the instanced Visual node.
static func _enemy_name(visual_root: Node3D) -> String:
	for node in visual_root.find_children("*", "Node3D", true, false):
		var file := node.scene_file_path.get_file()
		if file.ends_with("_rig.tscn"):
			return file.trim_suffix("_rig.tscn")
	return ""


static func _body_mesh(skeleton: Skeleton3D) -> MeshInstance3D:
	for node in skeleton.get_children():
		if node is MeshInstance3D and node.name != NODE_NAME and (node as MeshInstance3D).skin != null:
			return node
	return null


static var _piece_data := {}


## Costume of a severed part as one static mesh around `center` (the body piece's centre) in the
## current pose, or {} when the actor wears none. `body_data` is the body's prepared mesh data.
static func costume_piece(skeleton: Skeleton3D, body_data: Dictionary, chain: PackedInt32Array, center: Vector3) -> Dictionary:
	var costume := skeleton.get_node_or_null(NODE_NAME) as MeshInstance3D
	if costume == null or not costume.visible:
		return {}
	var mesh := costume.mesh as ArrayMesh
	if not _piece_data.has(mesh):
		var surfaces: Array = []
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			surfaces.append({
				"vertices": arrays[Mesh.ARRAY_VERTEX], "normals": arrays[Mesh.ARRAY_NORMAL],
				"uvs": PackedVector2Array(), "colors": arrays[Mesh.ARRAY_COLOR],
				"bones": arrays[Mesh.ARRAY_BONES], "weights": arrays[Mesh.ARRAY_WEIGHTS],
				"indices": arrays[Mesh.ARRAY_INDEX], "stride": 4,
			})
		_piece_data[mesh] = {"surfaces": surfaces}
	var data: Dictionary = (_piece_data[mesh] as Dictionary).duplicate()
	data.binds = body_data.binds
	var materials: Array = []
	for surface in mesh.get_surface_count():
		materials.append(mesh.surface_get_material(surface))
	return MESH.build_piece(data, chain, skeleton, materials, center)


## Adds the costume of a severed part to its piece, so a limb keeps its sleeve.
static func dress_piece(piece: Node3D, skeleton: Skeleton3D, body_data: Dictionary, chain: PackedInt32Array, center: Vector3) -> void:
	var dressed := costume_piece(skeleton, body_data, chain, center)
	if not dressed.is_empty():
		var clothes := MeshInstance3D.new()
		clothes.mesh = dressed.mesh
		piece.add_child(clothes)
