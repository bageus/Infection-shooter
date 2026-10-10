@tool
extends EditorScenePostImport
## Share immutable authored materials across every group-04 model and damage stage.

const MATERIALS := {
	"Group04Opaque": preload("res://models/objects/enviroments/04/materials/group04_opaque.tres"),
	"Group04OpaqueDoubleSided": preload("res://models/objects/enviroments/04/materials/group04_opaque_double_sided.tres"),
}


func _post_import(scene: Node) -> Object:
	_visit(scene)
	return scene


func _visit(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source: Material = mesh.get_active_material(surface)
			if source != null and MATERIALS.has(source.resource_name):
				mesh.mesh.surface_set_material(surface, MATERIALS[source.resource_name])
	for child: Node in node.get_children():
		_visit(child)
