@tool
extends EditorScenePostImport
## Immutable materials and empty damage placeholders; authored UVs stay unchanged.
const STAGES := preload("res://models/objects/enviroments/05/lazy_stages.json")
const MATERIALS := {
	"Lamp_Diffuser__abd991dc": preload("res://models/objects/enviroments/05/materials/group05_00.tres"),
	"05_desk_phone_Readable_Key_Legends__3161f91b": preload("res://models/objects/enviroments/05/materials/group05_01.tres"),
	"05_keyboard_Readable_Key_Legends__c2fc9883": preload("res://models/objects/enviroments/05/materials/group05_02.tres"),
	"Amber_ABS__f3e6ff66": preload("res://models/objects/enviroments/05/materials/group05_03.tres"),
	"Blue_Sensor_Glass__02dca743": preload("res://models/objects/enviroments/05/materials/group05_04.tres"),
	"Cool_Grey_Keycaps__f618a3e6": preload("res://models/objects/enviroments/05/materials/group05_05.tres"),
	"Dark_Display_Glass__11d04523": preload("res://models/objects/enviroments/05/materials/group05_06.tres"),
	"Dark_Display_Glass__b0320395": preload("res://models/objects/enviroments/05/materials/group05_07.tres"),
	"Electronics_Interior__ddbff03a": preload("res://models/objects/enviroments/05/materials/group05_08.tres"),
	"Graphite_ABS__3f132540": preload("res://models/objects/enviroments/05/materials/group05_09.tres"),
	"Graphite_ABS__d7aeb6a7": preload("res://models/objects/enviroments/05/materials/group05_10.tres"),
	"Pearl_White_ABS_Tinted__18faec4a": preload("res://models/objects/enviroments/05/materials/group05_11.tres"),
	"Pearl_White_ABS__95ccd953": preload("res://models/objects/enviroments/05/materials/group05_12.tres"),
	"Pearl_White_ABS__f5c8b020": preload("res://models/objects/enviroments/05/materials/group05_13.tres"),
	"Raw_Plastic_Core__083d0e7a": preload("res://models/objects/enviroments/05/materials/group05_14.tres"),
	"Raw_Plastic_Core__be501a48": preload("res://models/objects/enviroments/05/materials/group05_15.tres"),
	"Red_ABS__99a13f4f": preload("res://models/objects/enviroments/05/materials/group05_16.tres"),
	"Rubber_And_Interior__4b647e00": preload("res://models/objects/enviroments/05/materials/group05_17.tres"),
	"Satin_Aluminium_Chassis__87a5bb86": preload("res://models/objects/enviroments/05/materials/group05_18.tres"),
	"Satin_Aluminium_Tinted__9089e24d": preload("res://models/objects/enviroments/05/materials/group05_19.tres"),
	"Satin_Aluminium__818c4e3e": preload("res://models/objects/enviroments/05/materials/group05_20.tres"),
	"Satin_Graphite_ABS__0ddf32bb": preload("res://models/objects/enviroments/05/materials/group05_21.tres"),
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
