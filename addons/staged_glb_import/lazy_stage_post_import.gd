@tool
extends EditorScenePostImport
## Import script for destructible models whose damage stages are separate GLBs.
const PLACEHOLDERS := preload("res://addons/staged_glb_import/lazy_stage_placeholders.gd")


func _post_import(scene: Node) -> Object:
	PLACEHOLDERS.add(scene, get_source_file())
	return scene
