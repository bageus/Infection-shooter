extends RefCounted
## One flat soft shadow under the hero and every infected, shown only while real
## shadows are off (settings), so a character never floats without any shadow.
## Attached through the tree's node_added signal, so no character scene changes.
## The quad and its material are shared: one draw item per character, no light.

const SHADER := preload("res://game/core/vfx/public/character_blob_shadow.gdshader")
const GROUP := &"character_blob_shadows"
const WATCHED_GROUPS: Array[StringName] = [&"player", &"infected"]
## Shadow diameter in capsule radii, and its lift above the capsule's lowest point.
const SPAN := 2.8
const LIFT := 0.02
static var _shadows_allowed := true
static var _quad: QuadMesh
static var _material: ShaderMaterial
static var _tracked: SceneTree


## Starts shadowing every present and future character of the tree.
static func track(tree: SceneTree) -> void:
	if tree == null or _tracked == tree:
		return
	_tracked = tree
	tree.node_added.connect(_node_added)
	for group in WATCHED_GROUPS:
		for node in tree.get_nodes_in_group(group):
			attach(node)


## The shadow setting: blobs show only while real shadows are off.
static func set_shadows_allowed(tree: SceneTree, allowed: bool) -> void:
	_shadows_allowed = allowed
	if tree != null:
		tree.call_group(GROUP, &"set_visible", not allowed)


## Adds the blob below a character body's capsule; false when it has none or already has one.
static func attach(node: Node) -> bool:
	var body := node as CharacterBody3D
	var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D if body != null else null
	var capsule := shape.shape as CapsuleShape3D if shape != null else null
	if capsule == null or body.has_node("BlobShadow"):
		return false
	var blob := MeshInstance3D.new()
	blob.name = "BlobShadow"
	blob.set_meta("planning_bounds_excluded", true)
	blob.mesh = _shared_quad()
	blob.material_override = _shared_material()
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.scale = Vector3.ONE * capsule.radius * SPAN
	blob.position = shape.position - Vector3(0.0, capsule.height * 0.5 - LIFT, 0.0)
	blob.visible = not _shadows_allowed
	blob.add_to_group(GROUP)
	body.add_child(blob)
	# A dead enemy lies down: its blob would stay behind on the floor.
	if body.has_signal(&"blood_death"):
		body.connect(&"blood_death", blob.queue_free.unbind(3))
	return true


static func _node_added(node: Node) -> void:
	for group in WATCHED_GROUPS:
		if node.is_in_group(group):
			attach.call_deferred(node)
			return


static func _shared_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.orientation = PlaneMesh.FACE_Y
		_quad.size = Vector2.ONE
	return _quad


static func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.render_priority = -2
	return _material
