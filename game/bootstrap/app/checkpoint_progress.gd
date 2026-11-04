extends RefCounted
## Furthest checkpoint map the player has passed, kept apart from the level chain.
## "Continue" in the main menu starts the chain map that follows it.

const LEVEL_CHAIN := preload("res://game/bootstrap/app/level_chain.gd")
const PLANNING_STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const PATH := "user://checkpoint_progress.json"
const VERSION := 1


static func passed_map() -> String:
	if not FileAccess.file_exists(PATH):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return ""
	return str(data.get("passed", ""))


static func save_passed(map_name: String) -> Error:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"version": VERSION, "passed": map_name}, "\t"))
	return OK


## Map that "Continue" starts, or "" when no checkpoint was passed or nothing follows it.
static func resume_map() -> String:
	var passed := passed_map()
	if passed.is_empty():
		return ""
	var chain: RefCounted = LEVEL_CHAIN.new()
	chain.load_file()
	return chain.name_after(passed)


## Called when a map is completed. A checkpoint map becomes the saved progress unless a further one is already saved.
static func on_completed(map_name: String) -> void:
	var chain: RefCounted = LEVEL_CHAIN.new()
	chain.load_file()
	var index: int = chain.index_of(map_name)
	if index < 0 or not chain.is_checkpoint(index):
		return
	var saved: int = chain.index_of(passed_map())
	if saved < index:
		save_passed(map_name)


## Scene file of a chain map, read the same way the planner reads it.
static func map_file(map_name: String) -> String:
	return PLANNING_STORAGE.new().read_map_path(map_name)
