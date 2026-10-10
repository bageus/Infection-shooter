extends SceneTree
const MAP := preload("res://game/bootstrap/app/planning_map_file.gd")
const PRIMARY := "user://p1_map_test.json"
const DEFAULT := "user://p1_default_test.json"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_clean()
	var first := {"version": 8, "objects": [{"scene": "res://old.tscn", "x": 1}]}
	var second := {"version": 8, "objects": [{"scene": "res://new.tscn", "x": 2}]}
	_expect(not MAP.write(PRIMARY, first).has("error"), "First map is verified and committed")
	_expect(not MAP.write(PRIMARY, second).has("error"), "Replacement is committed")
	_expect(MAP.read(PRIMARY).data.objects[0].x == 2, "Current map contains new data")
	_expect(MAP.read(PRIMARY + ".bak").data.objects[0].x == 1, "Backup contains the previous valid map")
	var saved := FileAccess.get_file_as_bytes(PRIMARY)
	_expect(MAP.write(PRIMARY, {"objects": null}).has("error"), "Invalid map cannot be written")
	_expect(FileAccess.get_file_as_bytes(PRIMARY) == saved, "Validation failure preserves current bytes")
	DirAccess.make_dir_absolute(PRIMARY + ".tmp")
	_expect(MAP.write(PRIMARY, first).has("error"), "Temporary write failure is reported")
	_expect(FileAccess.get_file_as_bytes(PRIMARY) == saved, "Temporary write failure preserves current bytes")
	DirAccess.remove_absolute(PRIMARY + ".tmp")
	DirAccess.make_dir_absolute(PRIMARY + ".bak.tmp")
	_expect(MAP.write(PRIMARY, first).has("error"), "Backup preparation failure aborts commit")
	_expect(FileAccess.get_file_as_bytes(PRIMARY) == saved, "Backup failure preserves current bytes")
	DirAccess.remove_absolute(PRIMARY + ".bak.tmp")
	_write(PRIMARY + ".tmp", "{interrupted")
	_expect(MAP.startup(PRIMARY, DEFAULT).data.objects[0].x == 2, "Interrupted temporary file is ignored on startup")
	_expect(not MAP.write(DEFAULT, {"version": 8, "objects": []}).has("error"), "Explicit empty shipped map remains valid")
	_write(PRIMARY, "{corrupt")
	var broken := FileAccess.get_file_as_bytes(PRIMARY)
	var recovery := MAP.startup(PRIMARY, DEFAULT)
	_expect(recovery.has("error") and recovery.recovery.size() == 2, "Invalid JSON offers backup and shipped map")
	_expect(FileAccess.get_file_as_bytes(PRIMARY) == broken, "Recovery inspection does not alter corrupt evidence")
	DirAccess.remove_absolute(PRIMARY)
	_expect(MAP.startup(PRIMARY, DEFAULT).recovery.size() == 2, "Missing primary with a valid backup offers recovery")
	_write(PRIMARY, "{corrupt")
	_expect(not MAP.write(PRIMARY, second).has("error"), "User can deliberately save a corrected map")
	_expect(MAP.read(PRIMARY + ".bak").data.objects[0].x == 1, "Correcting corruption retains last valid backup")
	_write(PRIMARY, '{"objects":"invalid schema"}')
	_expect(MAP.startup(PRIMARY, DEFAULT).has("error"), "Valid JSON with invalid schema enters recovery")
	_write(PRIMARY + ".bak", "{broken too")
	_expect(MAP.startup(PRIMARY, DEFAULT).recovery.size() == 1, "Invalid backup is not offered")
	DirAccess.remove_absolute(PRIMARY)
	DirAccess.remove_absolute(PRIMARY + ".bak")
	_expect(MAP.startup(PRIMARY, DEFAULT).data.objects.is_empty(), "Fresh installation loads the shipped map")
	_clean()
	print("Map file tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	for path in [PRIMARY, DEFAULT]:
		for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path + suffix) or DirAccess.dir_exists_absolute(path + suffix):
				DirAccess.remove_absolute(path + suffix)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
