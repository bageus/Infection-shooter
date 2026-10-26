extends SceneTree
const MIGRATION := preload("res://game/bootstrap/app/user_data_migration.gd")
var failures := 0


func _initialize() -> void:
	var current := ProjectSettings.globalize_path("user://").rstrip("/")
	var old_dir := current.get_base_dir().path_join(MIGRATION.OLD_NAMES[0])
	var existed := DirAccess.dir_exists_absolute(old_dir)
	if existed:
		print("Old user folder already exists on this machine; skipping to keep its data safe.")
		quit(0)
		return
	DirAccess.remove_absolute(MIGRATION.MARKER)
	DirAccess.make_dir_recursive_absolute(old_dir.path_join("maps"))
	_write(old_dir.path_join("maps/a.json"), "old map")
	_write(old_dir.path_join("planned_layout.json"), "old layout")
	DirAccess.make_dir_recursive_absolute(current)
	_write(current.path_join("planned_layout.json"), "new layout")
	var copied: int = MIGRATION.run()
	_check(copied == 1, "copies only the missing file, got %d" % copied)
	_check(FileAccess.get_file_as_string("user://maps/a.json") == "old map", "map copied")
	_check(FileAccess.get_file_as_string("user://planned_layout.json") == "new layout", "existing file kept")
	_write(old_dir.path_join("later.json"), "x")
	_check(MIGRATION.run() == 0 and not FileAccess.file_exists("user://later.json"), "runs once")
	for path in ["user://maps/a.json", "user://planned_layout.json", MIGRATION.MARKER]:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://maps")
	OS.move_to_trash(old_dir)
	print("User data migration tests: %d failures" % failures)
	quit(failures)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
