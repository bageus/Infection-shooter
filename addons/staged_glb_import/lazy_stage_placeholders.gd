@tool
extends RefCounted
## Adds a hidden placeholder per damage stage that lives in its own GLB.
## environment_prop_geometry.ensure_group() loads the stage on first use.

const STAGES := preload("res://models/objects/enviroments/lazy_stages.json")


static func add(scene: Node, source_file: String) -> void:
	var entries: Array = STAGES.data.get(source_file.get_file(), [])
	for entry: Dictionary in entries:
		var placeholder := Node3D.new()
		placeholder.name = str(entry["name"])
		placeholder.scale = Vector3.ZERO
		placeholder.set_meta(&"lazy_stage_path", str(entry["path"]))
		scene.add_child(placeholder)
		placeholder.owner = scene
	if not entries.is_empty():
		scene.set_meta(&"staged_glb_version", 2)
