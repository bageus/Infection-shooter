extends RefCounted
## Description texts of a chain map: shown before it starts and after it is completed.

const LEVEL_CHAIN := preload("res://game/bootstrap/app/level_chain.gd")


static func before(map_name: String) -> String:
	return _text(map_name, "description_before")


static func after(map_name: String) -> String:
	return _text(map_name, "description_after")


static func _text(map_name: String, key: String) -> String:
	if map_name.is_empty():
		return ""
	var chain: RefCounted = LEVEL_CHAIN.new()
	chain.load_file()
	return chain.description(chain.index_of(map_name), key)
