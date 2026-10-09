@tool
extends EditorScenePostImport

const SHARED_TEXTURES := preload("res://addons/staged_glb_import/shared_texture_import.gd")


func _post_import(scene: Node) -> Object:
	if SHARED_TEXTURES.process(scene) != OK:
		push_error("Embedded texture optimization failed: " + get_source_file())
	return scene
