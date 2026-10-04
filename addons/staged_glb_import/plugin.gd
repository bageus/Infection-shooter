@tool
extends EditorPlugin
## Registers the staged GLB import extension. The first time the plugin runs in
## a project whose cache was imported without it, multi-scene models are
## reimported once so their damage stages become available.

const EXTENSION := preload("res://addons/staged_glb_import/staged_glb_extension.gd")
const MODELS := "res://models/objects/enviroments"

var _extension: GLTFDocumentExtension


func _enter_tree() -> void:
	_extension = EXTENSION.new()
	GLTFDocument.register_gltf_document_extension(_extension, true)
	var settings := EditorInterface.get_editor_settings()
	if int(settings.get_project_metadata("staged_glb_import", "version", 0)) < EXTENSION.VERSION:
		settings.set_project_metadata("staged_glb_import", "version", EXTENSION.VERSION)
		_reimport_staged.call_deferred()


func _exit_tree() -> void:
	if _extension != null:
		GLTFDocument.unregister_gltf_document_extension(_extension)
		_extension = null


func _reimport_staged() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.is_scanning():
		await filesystem.filesystem_changed
	var paths := PackedStringArray()
	_collect(MODELS, paths)
	if not paths.is_empty():
		filesystem.reimport_files(paths)


static func _collect(directory: String, paths: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(directory):
		_collect(directory.path_join(sub), paths)
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() == "glb" and _scene_count(directory.path_join(file)) > 1:
			paths.append(directory.path_join(file))


# Number of non-empty glTF scenes, read from the GLB JSON chunk only.
static func _scene_count(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_32() != 0x46546C67:
		return 0
	file.get_32()
	file.get_32()
	var length := file.get_32()
	file.get_32()
	var json: Variant = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	if not json is Dictionary:
		return 0
	var count := 0
	for scene in (json as Dictionary).get("scenes", []):
		if not (scene as Dictionary).get("nodes", []).is_empty():
			count += 1
	return count
