extends RefCounted
## Verified same-directory replacement; never truncate the current map.
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")


static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot open map (%d)" % FileAccess.get_open_error()}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"error": "invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
	if not parser.data is Dictionary:
		return {"error": "map must be an object"}
	var problem := VALIDATOR.error(parser.data)
	return {"data": parser.data} if problem.is_empty() else {"error": problem}


static func write(path: String, data: Dictionary) -> Dictionary:
	var problem := VALIDATOR.error(data)
	if not problem.is_empty():
		return {"error": problem}
	var text := JSON.stringify(data, "\t")
	var temporary := path + ".tmp"
	var error := _write_verified(temporary, text)
	if not error.is_empty():
		return {"error": error}
	# Keep the last valid map, not a corrupt current file, as the recovery copy.
	if FileAccess.file_exists(path) and not read(path).has("error"):
		var old := FileAccess.get_file_as_string(path)
		error = _write_verified(path + ".bak.tmp", old)
		if not error.is_empty():
			return {"error": "backup: " + error}
		var backup_error := DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak")
		if backup_error != OK:
			return {"error": "cannot replace backup (%d)" % backup_error}
	var replace_error := DirAccess.rename_absolute(temporary, path)
	if replace_error != OK:
		return {"error": "cannot replace map (%d); recovery copy retained" % replace_error}
	return {"saved": true}


static func _write_verified(path: String, text: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot open temporary file (%d)" % FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return "cannot write temporary file (%d)" % error
	if FileAccess.get_file_as_string(path) != text or read(path).has("error"):
		return "temporary file verification failed"
	return ""


static func startup(primary: String, fallback: String) -> Dictionary:
	if not FileAccess.file_exists(primary) and not FileAccess.file_exists(primary + ".bak"):
		return read(fallback)
	var result := read(primary)
	if not result.has("error"):
		return result
	var choices: Array[Dictionary] = []
	for candidate: Dictionary in [{"path": primary + ".bak", "kind": "backup"}, {"path": fallback, "kind": "default"}]:
		if not read(candidate.path).has("error"):
			choices.append(candidate)
	result["recovery"] = choices
	return result
