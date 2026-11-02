extends RefCounted
## The map the game starts with: the last one saved with SAVE MAP, until SAVE LAYOUT saves the start layout again.
## Without this a map saved by name (with its quests) would only come back when loaded by hand.

const PATH := "user://startup_map.cfg"


static func map_name() -> String:
	var config := ConfigFile.new()
	return str(config.get_value("startup", "map", "")) if config.load(PATH) == OK else ""


static func remember(name: String) -> void:
	var config := ConfigFile.new()
	config.set_value("startup", "map", name)
	config.save(PATH)


static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
