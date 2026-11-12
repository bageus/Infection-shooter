extends SceneTree
## Debug main-menu map list: shipped and saved planner maps, each path must open.

const PICKER := preload("res://game/bootstrap/app/menu/debug_map_list.gd")
const STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const SAMPLE := "zz_debug_picker_sample"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sample_path: String = STORAGE.MAPS_DIR + "/" + SAMPLE + ".json"
	DirAccess.make_dir_recursive_absolute(STORAGE.MAPS_DIR)
	FileAccess.open(sample_path, FileAccess.WRITE).store_string("{}")
	var rows := PICKER.entries()
	var labels: Array = rows.map(func(row: Dictionary) -> String: return row.label)
	_check(labels.has(SAMPLE) and not rows.filter(func(row: Dictionary) -> bool: return row.path == sample_path and not row.shipped).is_empty(), "saved map is listed from user maps")
	_check(rows.all(func(row: Dictionary) -> bool: return FileAccess.file_exists(row.path)), "every listed map file exists")
	DirAccess.remove_absolute(sample_path)
	print("debug map picker tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
