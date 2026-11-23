extends SceneTree
## Shelf templates: desks whose names share a prefix (regr_case / regr_case_small) keep their own templates, and templates saved before models moved into subfolders still list and load.
const FILES := preload("res://game/bootstrap/app/desk_setup_template_files.gd")
const BOOK := "res://models/objects/enviroments/09/books/09_book_big.glb"
const OLD_BOOK := "res://models/objects/enviroments/09/09_book_big.glb"
const OLD_FILE := "user://desk_setups/regr_old_shelf_template_old_path.json"
var failures := 0


class Migrator extends RefCounted:
	func migrate(path: String) -> String:
		return BOOK if path == OLD_BOOK else path


func _initialize() -> void:
	var zones := [{"name": "Shelf", "x": 0.0, "z": 0.0, "width": 0.5, "depth": 0.3, "height": 0.5, "floor": false, "category": "Books", "required": false}]
	var payload := {"version": 1, "desk": "regr_case_small", "front": 0, "zones": zones, "items": [{"path": BOOK, "zone": 0, "x": 0.0, "y": 0.5, "z": 0.0, "yaw": 0.0}]}
	_check(FILES.save("regr_case_small", "shelf_small", payload), "Small case template saved")
	payload.desk = "regr_case"
	_check(FILES.save("regr_case", "shelf_big", payload), "Case template saved")
	var names: Array = FILES.list_for("regr_case").map(func(item: Dictionary) -> String: return item.name)
	_check(names.has("shelf_big") and not names.has("small_shelf_small"), "Prefix-sharing desk keeps only its own templates: %s" % str(names))

	# A template written before the book models moved into 09/books still names the old path.
	payload.desk = "regr_old"
	payload.items[0].path = OLD_BOOK
	var file := FileAccess.open(OLD_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	var migrator := Migrator.new()
	var migrate := Callable(migrator, "migrate")
	_check(FILES.list_for("regr_old").is_empty(), "Old path is not listed without migration")
	_check(FILES.list_for("regr_old", migrate).size() == 1, "Old path is listed after migration")
	_check(not FILES.load(OLD_FILE, "regr_old", migrate).is_empty(), "Old path loads after migration")

	DirAccess.remove_absolute(OLD_FILE)
	for item in FILES.list_for("regr_case"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(item.path))
	for item in FILES.list_for("regr_case_small"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(item.path))
	print("Shelf template tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
		print("FAIL: " + message)
