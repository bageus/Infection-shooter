extends RefCounted
## A visual copy shares the live mesh/skin and follows the same skeleton.
const SHADER := preload("res://game/bootstrap/app/occlusion_silhouette.gdshader")
const MATERIALS := preload("res://game/bootstrap/app/occlusion_wall_materials.gd")
var target: WeakRef
var color: Color
var copies: Array[MeshInstance3D] = []
var textured := false
var _materials := MATERIALS.new()


func _init(node: Node3D, tint: Color, use_texture: bool = false) -> void:
	target = weakref(node)
	color = tint
	textured = use_texture


func set_revealed(value: bool, force_visible: bool = false) -> void:
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
			# Above darkness covers (priority 10), so the hero is not dimmed by them.
			material.render_priority = 20
			copy.material_override = material
			if textured:
				copy.material_override = null
				for surface in source.mesh.get_surface_count():
					var authored := source.get_active_material(surface) as BaseMaterial3D
					var pass_material := _materials._copy_surface(authored, true) if authored != null else material
					pass_material.render_priority = 20
					copy.set_surface_override_material(surface, pass_material)
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
			if source != null:
				for index in source.get_blend_shape_count():
					copy.set_blend_shape_value(index, source.get_blend_shape_value(index))
			for index in copy.mesh.get_surface_count():
				var material := copy.get_active_material(index) as ShaderMaterial
				if material != null:
					material.set_shader_parameter("force_visible", force_visible)
			copy.show()


func clear() -> void:
	for copy in copies:
		if is_instance_valid(copy):
			copy.free()
	copies.clear()
	_materials.clear()
