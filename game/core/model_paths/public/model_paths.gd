extends RefCounted
## Environment models live in topic subfolders of their group ("09/books/...").
## "damage" folders hold lazily loaded stages and never count as models.

const ROOT := "res://models/objects/enviroments/"


static func list(group: String) -> Array[String]:
	var result: Array[String] = []
	_collect(ROOT + group, result)
	return result


static func find(group: String, file: String) -> String:
	for path in list(group):
		if path.get_file() == file:
			return path
	return ""


static func _collect(directory: String, result: Array[String]) -> void:
	# ResourceLoader also lists models in exported builds, where the source
	# .glb files are replaced by their imported resources.
	for entry: String in ResourceLoader.list_directory(directory):
		if entry.ends_with("/"):
			if entry != "damage/":
				_collect(directory + "/" + entry.trim_suffix("/"), result)
		elif entry.to_lower().ends_with(".glb"):
			result.append(directory + "/" + entry)
