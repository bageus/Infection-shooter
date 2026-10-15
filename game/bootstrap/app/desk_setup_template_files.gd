extends RefCounted

# Versioned user templates; the level layout continues to own placed instances.
const SCHEMA := preload("res://game/bootstrap/app/desk_setup_template_schema.gd")
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
	if safe.is_empty() or not desk_type.is_valid_identifier() or not SCHEMA.valid(payload, desk_type):
		return false
	if desk_type.is_empty() or DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT)) != OK:
		return false
	var path := ROOT + "/" + desk_type + "_" + safe + ".json"
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.flush()
	var written := file.get_error() == OK
	file.close()
	if not written:
		DirAccess.remove_absolute(temporary)
		return false
	var check := FileAccess.open(temporary, FileAccess.READ)
	if check == null:
		return false
	var decoded: Variant = JSON.parse_string(check.get_as_text())
	check.close()
	if not SCHEMA.valid(decoded, desk_type):
		DirAccess.remove_absolute(temporary)
		return false
	return DirAccess.rename_absolute(temporary, path) == OK


static func list_for(desk_type: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var folder := DirAccess.open(ROOT)
	if folder == null:
		return results
	var prefix := desk_type + "_"
	for file in folder.get_files():
		if file.begins_with(prefix) and file.ends_with(".json"):
			results.append({"name": file.trim_prefix(prefix).trim_suffix(".json"), "path": ROOT + "/" + file})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return results


static func load(path: String, desk_type: String) -> Dictionary:
	if not desk_type.is_valid_identifier() or path.get_base_dir() != ROOT or not path.begins_with(ROOT + "/" + desk_type + "_") or not path.ends_with(".json"):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if SCHEMA.valid(data, desk_type):
		return data
	return {}
