extends RefCounted

# Versioned user templates; the level layout continues to own placed instances.
const ROOT := "user://desk_setups"


static func safe_name(value: String) -> String:
	var result := ""
	for letter in value.to_lower():
		if letter.is_valid_identifier() or letter.is_valid_int():
			result += letter
		elif letter in [" ", "-"]:
			result += "_"
	return result.trim_prefix("_").trim_suffix("_")


static func save(desk_type: String, name_part: String, payload: Dictionary) -> bool:
	var safe := safe_name(name_part)
	if safe.is_empty():
		return false
	if DirAccess.make_dir_recursive_absolute(ROOT) != OK:
		return false
	var file := FileAccess.open(ROOT + "/" + desk_type + "_" + safe + ".json", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	return true


static func list_for(desk_type: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var folder := DirAccess.open(ROOT)
	if folder == null:
		return results
	var prefix := desk_type + "_"
	for file in folder.get_files():
		if file.begins_with(prefix) and file.ends_with(".json"):
			results.append({"name": file.trim_prefix(prefix).trim_suffix(".json"), "path": ROOT + "/" + file})
	return results


static func load(path: String, desk_type: String) -> Dictionary:
	if not path.begins_with(ROOT + "/" + desk_type + "_") or not path.ends_with(".json"):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary and data.get("version") == 1 and data.get("desk") == desk_type:
		return data
	return {}
