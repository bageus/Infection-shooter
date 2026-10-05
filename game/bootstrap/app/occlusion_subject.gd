extends RefCounted
## A visual copy shares the live mesh/skin and follows the same skeleton.
const SHADER := preload("res://game/bootstrap/app/occlusion_silhouette.gdshader")
var target: WeakRef
var color: Color
var copies: Array[MeshInstance3D] = []


func _init(node: Node3D, tint: Color) -> void:
	target = weakref(node)
	color = tint


func set_revealed(value: bool) -> void:
	if not value:
		for copy in copies:
			if is_instance_valid(copy):
				copy.hide()
		return
	var node := target.get_ref() as Node3D
	if node == null:
		return
	if copies.is_empty():
		for source: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			if source.mesh == null or source.has_meta("occlusion_copy") or source.mesh is QuadMesh:
				continue
			var copy := MeshInstance3D.new()
			copy.name = "OccludedSilhouette"
			copy.set_meta("occlusion_copy", true)
			copy.mesh = source.mesh
			copy.skin = source.skin
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var material := ShaderMaterial.new()
			material.shader = SHADER
			material.set_shader_parameter("tint", color)
			copy.material_override = material
			source.add_child(copy)
			var skeleton := source.get_node_or_null(source.skeleton)
			if skeleton is Skeleton3D:
				copy.skeleton = copy.get_path_to(skeleton)
			copies.append(copy)
	for copy in copies:
		if is_instance_valid(copy):
			var source := copy.get_parent() as MeshInstance3D
			if source != null and copy.mesh != source.mesh:
				copy.mesh = source.mesh
			copy.show()


func clear() -> void:
	for copy in copies:
		if is_instance_valid(copy):
			copy.free()
	copies.clear()
