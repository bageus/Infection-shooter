extends RefCounted
## Furthest checkpoint map the player has entered, kept apart from the level chain.
## "Continue" in the main menu restarts that map with the loadout it was first entered with.

const LEVEL_CHAIN := preload("res://game/bootstrap/app/level_chain.gd")
const PLANNING_STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const PATH := "user://checkpoint_progress.json"
const VERSION := 1


## Forgets the saved checkpoint; a new operation starts from the first map.
static func clear() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func passed_map() -> String:
	if not FileAccess.file_exists(PATH):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return ""
	return str(data.get("passed", ""))


## Weapons, armor, ammo and DNA saved with the checkpoint ({} for a file saved without them).
static func passed_carry() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return {}
	var carry: Variant = data.get("carry", {})
	return carry if carry is Dictionary else {}


static func save_passed(map_name: String, carry: Dictionary = {}) -> Error:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": VERSION, "passed": map_name, "carry": carry}, "\t"))
	return OK


## Map that "Continue" starts: the checkpoint map first entered, or "" when none was entered.
static func resume_map() -> String:
	var passed := passed_map()
	if passed.is_empty():
		return ""
	var chain: RefCounted = LEVEL_CHAIN.new()
	chain.load_file()
	return passed if chain.index_of(passed) >= 0 else ""


## Called when a map is entered with the loadout the player brings. A checkpoint map becomes the saved
## progress the first time it is entered, unless a further one is already saved.
static func on_entered(map_name: String, carry: Dictionary = {}) -> void:
	var chain: RefCounted = LEVEL_CHAIN.new()
	chain.load_file()
	var index: int = chain.index_of(map_name)
	if index < 0 or not chain.is_checkpoint(index):
		return
	var saved: int = chain.index_of(passed_map())
	if saved < index:
		save_passed(map_name, carry)


## Scene file of a chain map, read the same way the planner reads it.
static func map_file(map_name: String) -> String:
	return PLANNING_STORAGE.new().read_map_path(map_name)
