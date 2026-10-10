extends SceneTree
## Run with --main-pack PACK --script absolute/path/to/this/script.
## Uses Godot's own pack reader, including new PCK formats and remaps.
var files: Array[String] = []


func _initialize() -> void:
	_walk("res://")
	files.sort()
	var output := OS.get_environment("EXPORT_INVENTORY")
	if output.is_empty():
		push_error("EXPORT_INVENTORY must name the output JSON")
		quit(1)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(files, "\t"))
	file.close()
	print("Export inventory: %d packed files" % files.size())
	quit()


func _walk(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if directory.current_is_dir():
				_walk(child)
			else:
				files.append(child)
		entry = directory.get_next()
	directory.list_dir_end()
