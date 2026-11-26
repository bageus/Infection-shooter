extends SceneTree
## Web arena pool: only arena_* maps, beaten ones drop out.

const POOL := preload("res://game/bootstrap/app/web_arena_pool.gd")
const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	WALLET.path = "user://web_progress_pool_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	WALLET.reset_cache()
	var folder := "user://arena_pool_test"
	DirAccess.make_dir_recursive_absolute(folder)
	for file in ["arena_office_1.json", "arena_street_1.json", "level_1.json", "arena_notes.txt"]:
		var handle := FileAccess.open(folder + "/" + file, FileAccess.WRITE)
		handle.store_string("{}")
		handle.close()
	var dirs := [folder, "user://no_such_dir"]
	_check(POOL.names(dirs) == ["arena_office_1", "arena_street_1"], "only arena maps count: %s" % [POOL.names(dirs)])
	WALLET.mark_beaten("arena_office_1")
	_check(POOL.remaining(dirs) == ["arena_street_1"], "a beaten arena drops out")
	WALLET.mark_beaten("arena_street_1")
	_check(POOL.remaining(dirs).is_empty(), "all beaten leaves nothing")
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder + "/" + file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WALLET.path))
	print("web arena pool tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
