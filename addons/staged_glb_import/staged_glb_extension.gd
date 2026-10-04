@tool
extends GLTFDocumentExtension
## Destructible models export each damage stage as its own glTF scene
## (Intact, Power_Off, LargeParts, SmallFragments, ...). Godot imports only
## the default scene, so this extension wraps every non-empty scene into a
## group node named after it. The default scene stays visible; the others
## get zero scale, the same hidden-stage convention the game already reveals
## (environment_damage.gd restores the scale when a stage is shown).

const META := &"staged_glb_version"
const VERSION := 1


func _import_post_parse(state: GLTFState) -> Error:
	var scenes: Array = state.json.get("scenes", [])
	var filled: Array[int] = []
	for i in scenes.size():
		if not (scenes[i] as Dictionary).get("nodes", []).is_empty():
			filled.append(i)
	if filled.size() < 2:
		return OK
	var default_scene := int(state.json.get("scene", 0))
	var nodes: Array[GLTFNode] = state.get_nodes()
	var roots := PackedInt32Array()
	for scene_index in filled:
		var scene: Dictionary = scenes[scene_index]
		var group := GLTFNode.new()
		group.original_name = str(scene.get("name", "Stage_%d" % scene_index))
		group.resource_name = group.original_name
		group.parent = -1
		group.height = 0
		if scene_index != default_scene:
			group.scale = Vector3.ZERO
		var group_index := nodes.size()
		var children := PackedInt32Array()
		for node_index in scene.get("nodes", []):
			children.append(int(node_index))
			nodes[int(node_index)].parent = group_index
		group.children = children
		nodes.append(group)
		roots.append(group_index)
	for root in roots:
		_set_heights(nodes, root, 0)
	state.set_nodes(nodes)
	state.root_nodes = roots
	state.set_additional_data(META, VERSION)
	return OK


func _import_post(state: GLTFState, root: Node) -> Error:
	if state.get_additional_data(META) != null:
		root.set_meta(META, VERSION)
	return OK


static func _set_heights(nodes: Array[GLTFNode], index: int, height: int) -> void:
	nodes[index].height = height
	for child in nodes[index].children:
		_set_heights(nodes, child, height + 1)
