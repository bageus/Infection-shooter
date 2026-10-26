extends RefCounted
## One-time copy of saves, maps and templates from the user folders of earlier project names.
## Existing files in the current folder are never overwritten; a marker stops later runs.

const OLD_NAMES: Array[String] = ["Infecrion shooter", "Template Game"]
const MARKER := "user://.migrated_old_user_data"


static func run() -> int:
	if FileAccess.file_exists(MARKER):
		return 0
	var copied := 0
	var current := ProjectSettings.globalize_path("user://")
	for old_name in OLD_NAMES:
		# app_userdata folders sit side by side, named after config/name.
		var old_dir := current.rstrip("/").get_base_dir().path_join(old_name)
		if old_dir != current.rstrip("/") and DirAccess.dir_exists_absolute(old_dir):
			copied += _copy_missing(old_dir, current.rstrip("/"))
	var marker := FileAccess.open(MARKER, FileAccess.WRITE)
	if marker != null:
		marker.store_string("migrated %d files" % copied)
	return copied


static func _copy_missing(from: String, to: String) -> int:
	var copied := 0
	DirAccess.make_dir_recursive_absolute(to)
	for name in DirAccess.get_files_at(from):
		var target := to.path_join(name)
		if not FileAccess.file_exists(target) and DirAccess.copy_absolute(from.path_join(name), target) == OK:
			copied += 1
	for name in DirAccess.get_directories_at(from):
		if name != "logs":
			copied += _copy_missing(from.path_join(name), to.path_join(name))
	return copied
