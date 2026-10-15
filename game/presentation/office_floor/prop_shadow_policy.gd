extends RefCounted
## Per-prop shadow eligibility from its intact local bounds and current world scale.
const MAX_SMALL_EXTENT := .4
const ORIGINAL := &"small_prop_original_shadow"
var _bounds := AABB()
var _scale := Vector3.INF
var _visual: Node3D
var _structural := true
var _small := false

func configure(body: Node3D, visual: Node3D, meshes: Array[MeshInstance3D], model_path: String) -> void:
	_visual = visual
	_structural = model_path.begins_with("res://models/objects/enviroments/01/")
	var found := false
	var inverse := body.global_transform.affine_inverse()
	for mesh in meshes:
		if not is_instance_valid(mesh) or mesh.mesh == null:
			continue
		var bounds: AABB = inverse * mesh.global_transform * mesh.get_aabb()
		_bounds = bounds if not found else _bounds.merge(bounds)
		found = true
	update(body)

func update(body: Node3D) -> void:
	if _visual == null or _structural:
		return
	var scale := body.global_basis.get_scale().abs()
	if scale.is_equal_approx(_scale):
		return
	_scale = scale
	var size := _bounds.size * scale
	var small := size.length_squared() > .000001 and maxf(size.x, maxf(size.y, size.z)) <= MAX_SMALL_EXTENT
	if small == _small:
		return
	_small = small
	if small:
		_disable(_visual)
	else:
		restore(_visual)

func apply_loaded_group(group: Node) -> void:
	if _small:
		_disable(group)

static func _disable(node: Node) -> void:
	if node is MeshInstance3D and node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		if not node.has_meta(ORIGINAL):
			node.set_meta(ORIGINAL, node.cast_shadow)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable(child)

static func restore(node: Node) -> void:
	if node is MeshInstance3D and node.has_meta(ORIGINAL):
		node.cast_shadow = int(node.get_meta(ORIGINAL))
		node.remove_meta(ORIGINAL)
	for child in node.get_children():
		restore(child)
