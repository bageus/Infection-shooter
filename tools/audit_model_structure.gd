extends SceneTree

const MODELS_DIR := "res://models/objects"

func _initialize() -> void:
	print("MODEL_AUDIT_V1")
	print("model_path,node_path,node_type,mesh_name,parent_node,child_count")
	var files := _find_models(MODELS_DIR)
	var failures := 0
	for path in files:
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("Cannot load model: %s" % path)
			failures += 1
			continue
		var root := packed.instantiate()
		_print_tree(path, root, "", "")
		root.free()
	print("MODEL_AUDIT_SUMMARY models=%d failures=%d" % [files.size(), failures])
	quit(1 if failures > 0 else 0)

func _find_models(directory: String) -> PackedStringArray:
	var result := PackedStringArray()
	_scan_directory(directory, result)
	result.sort()
	return result

func _scan_directory(directory: String, result: PackedStringArray) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		push_warning("Cannot open directory: %s" % directory)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var path := "%s/%s" % [directory, name]
			if dir.current_is_dir():
				_scan_directory(path, result)
			elif name.ends_with(".glb") or name.ends_with(".gltf"):
				result.append(path)
		name = dir.get_next()
	dir.list_dir_end()

func _print_tree(model_path: String, node: Node, relative_path: String, parent_name: String) -> void:
	var current_path := node.name if relative_path.is_empty() else "%s/%s" % [relative_path, node.name]
	var mesh_name := ""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			mesh_name = mi.mesh.resource_name
	var row := [
		_csv(model_path),
		_csv(current_path),
		_csv(node.get_class()),
		_csv(mesh_name),
		_csv(parent_name),
		str(node.get_child_count()),
	]
	print(",".join(row))
	for child in node.get_children():
		_print_tree(model_path, child, current_path, node.name)

func _csv(value: Variant) -> String:
	var text := str(value).replace(""", """")
	return ""%s"" % text
