@tool
extends EditorScenePostImport
## Group 03 shares immutable PBR materials; damage geometry is loaded on demand.
const STAGES := preload("res://models/objects/enviroments/03/lazy_stages.json")
const MATERIALS := {
	"Group03Opaque": preload("res://models/objects/enviroments/03/materials/group03_opaque.tres"),
	"Group03OpaqueSingleSided": preload("res://models/objects/enviroments/03/materials/group03_opaque_single_sided.tres"),
	"Group03Emission": preload("res://models/objects/enviroments/03/materials/group03_emission.tres"),
	"Group03Glass": preload("res://models/objects/enviroments/03/materials/group03_glass.tres"),
}


func _post_import(scene: Node) -> Object:
	_visit(scene)
	var data: Dictionary = STAGES.data
	for entry: Dictionary in data.get(get_source_file().get_file(), []):
		var placeholder := Node3D.new()
		placeholder.name = str(entry["name"])
		placeholder.scale = Vector3.ZERO
		placeholder.set_meta(&"lazy_stage_path", str(entry["path"]))
		scene.add_child(placeholder)
		placeholder.owner = scene
	if data.has(get_source_file().get_file()):
		scene.set_meta(&"staged_glb_version", 2)
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
