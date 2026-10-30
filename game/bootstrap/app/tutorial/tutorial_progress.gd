extends RefCounted
## Which tutorial lessons the player has already seen, kept in a small local file.

const FILE := "user://tutorial.cfg"
const SECTION := "lessons"

var path := FILE
var _done := {}


func _init(file_path: String = FILE) -> void:
	path = file_path
	var config := ConfigFile.new()
	if config.load(path) == OK:
		for id in config.get_section_keys(SECTION):
			_done[id] = bool(config.get_value(SECTION, id, false))


func is_done(id: String) -> bool:
	return bool(_done.get(id, false))


func mark_done(id: String) -> void:
	if is_done(id):
		return
	_done[id] = true
	var config := ConfigFile.new()
	config.load(path)
	config.set_value(SECTION, id, true)
	config.save(path)
