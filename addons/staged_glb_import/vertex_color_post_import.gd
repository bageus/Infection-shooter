@tool
extends EditorScenePostImport
## Models coloured only by COLOR_0: Godot leaves vertex colour off on some of their materials, so they import white.


func _post_import(scene: Node) -> Object:
	_visit(scene)
	return scene


func _visit(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.albedo_texture == null:
				material.vertex_color_use_as_albedo = true
	for child: Node in node.get_children():
		_visit(child)
