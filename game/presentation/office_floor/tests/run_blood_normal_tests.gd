extends SceneTree

const LIBRARY := preload("res://game/presentation/office_floor/blood_texture_library.gd")
const DECAL := preload("res://game/presentation/office_floor/blood_decal_prop.gd")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var library := LIBRARY.new()
	library.call("load_assets")
	for category in LIBRARY.CATEGORIES:
		var entries: Array = library.entries.get(category, [])
		_expect(entries.size() == LIBRARY.frame_count(category), "Every %s frame loads" % category)
		for entry: Dictionary in entries:
			var albedo: Texture2D = entry["texture"]
			var normal: Texture2D = entry.get("normal")
			_expect(normal != null, "%s_%02d has a normal map" % [category, entry["variant"]])
			if normal != null:
				_expect(normal.get_size() == albedo.get_size(), "%s_%02d normal matches its albedo footprint" % [category, entry["variant"]])
	var procedural := LIBRARY.new()
	procedural.call("load_assets", 512, 1.18, true)
	var generated: Array = procedural.entries.get("splatter", [])
	_expect(not generated.is_empty() and generated[0].get("normal") == null, "Procedural blood keeps no normal map")
	_expect(DECAL.texture_entry("pool_01").get("normal") != null, "Planner decal texture entry carries its normal map")
	print("run_blood_normal_tests: %d failure(s)" % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)
