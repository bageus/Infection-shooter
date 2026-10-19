extends RefCounted
## Swaps the alpha-blended glass surfaces of an imported model to the shared Fresnel shader.

const SHADER := preload("res://game/presentation/office_floor/glass_fresnel.gdshader")


static func apply(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if source != null and source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				# Imported meshes are shared by every pane; swapping on the mesh converts each material once.
				mesh_instance.mesh.surface_set_material(surface, _fresnel_from(source))
	for child in node.get_children():
		apply(child)


static func _fresnel_from(source: BaseMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("tint", source.albedo_color)
	material.set_shader_parameter("roughness", source.roughness)
	return material
