extends SceneTree
## Unavailable models stay in the authored document through real load/save/load.
const OBJECTS := preload("res://game/bootstrap/app/planning_objects.gd")
const STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const LOADER := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const CAPTURE := preload("res://game/bootstrap/app/planning_layout_capture.gd")
const MAP := preload("res://game/bootstrap/app/planning_map_file.gd")
const ASSET := "res://game/bootstrap/app/tests/fixtures/layout_object.tscn"
const RECOVER := "res://game/bootstrap/app/tests/fixtures/queue_model.tscn"
const ABSENT := "res://missing_unresolved_prop.tscn"
var failures := 0
var objects: Node
var storage: RefCounted
var session: Node
var path := ""

class Session extends Node:
	var root := Node3D.new()
	var enemies_root: Node3D
	var main_player := Node3D.new()
	var host: Node3D
	var active := false
	var edit_history := {"stack": []}

class FixtureObjects extends OBJECTS:
	func _update_status() -> void: pass

class Controls extends Node:
	var status := Label.new()
	func _update_history_buttons() -> void: pass

class Catalog extends RefCounted:
	var available := false
	var ENEMY_SCENES: Array = []
	var bind_asset: Callable
	func _migrate_scene_path(value: String) -> String:
		return "" if value == RECOVER and not available else value
	func _create_asset(value: String) -> Node3D:
		return (load(value) as PackedScene).instantiate() as Node3D

class Geometry extends RefCounted:
	func _restore_floor_surface(_node: Node3D, _path: String) -> void: pass

class FixtureStorage extends STORAGE:
	# Automatic wall fixture placement is unrelated to retaining unavailable records.
	func enforce_wall_fixtures() -> String: return ""


func _initialize() -> void: call_deferred("_run")


func _run() -> void:
	_setup()
	await _round_trips()
	await _transactions()
	await _recovery()
	_clear_and_replace()
	session.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("Unresolved map records tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _setup() -> void:
	session = Session.new()
	root.add_child(session)
	session.add_child(session.root)
	session.enemies_root = session.root
	session.add_child(session.main_player)
	var controls := Controls.new()
	controls.add_child(controls.status)
	session.add_child(controls)
	objects = FixtureObjects.new()
	session.add_child(objects)
	var catalog := Catalog.new()
	objects.configure({"session": session, "catalog": catalog, "controls": controls, "geometry": Geometry.new()})
	storage = FixtureStorage.new()
	storage.configure({"session": session, "objects": objects, "controls": controls, "catalog": catalog})
	storage.map_name_edit = LineEdit.new()
	session.add_child(storage.map_name_edit)
	storage.map_name_edit.text = "unresolved_map_test_%d" % OS.get_process_id()
	path = storage._map_path(storage.map_name_edit.text)


func _layout() -> Dictionary:
	var records: Array = []
	for index in 35: records.append({"scene": ASSET, "x": index, "object_id": "shown_%d" % index})
	records.insert(1, {"scene": RECOVER, "x": 4.25, "y": 2.5, "z": -8.0, "rotation_x": 12.0, "rotation_y": 37.0,
		"scale_x": 1.2, "object_id": "recover", "desk_id": "desk", "attachment": "desk", "zone": 7,
		"loot": {"kind": "ammo", "amount": 17}, "display": {"seed": 9}, "light_color": [0.2, 0.4, 0.8],
		"blood_attachment": {"owner": "wall", "mesh": "panel"}, "future_config": {"nested": [1, {"value": "original"}]}})
	for index in 2: records.append({"scene": ABSENT, "object_id": "missing_%d" % index, "x": index + 0.125})
	return {"version": 8, "objects": records}


func _hidden(data: Dictionary) -> Array:
	return (data.get("objects", []) as Array).filter(func(record: Dictionary) -> bool: return record.scene != ASSET)


func _round_trips() -> void:
	var initial := _layout()
	var expected := _hidden(initial).duplicate(true)
	var report: Dictionary = objects._apply_layout_data(initial)
	_expect(report.get("loaded") == 35 and report.get("skipped") == 3, "Missing and unmapped paths retain legacy load counts")
	initial.objects[1].future_config.nested[1].value = "input mutated"
	var captured: Dictionary = CAPTURE.collect(objects, objects.placed)
	_expect(_hidden(captured) == expected, "Capture retains every unavailable record and its nested configuration independently of input")
	var copy := _hidden(captured)
	if not copy.is_empty(): copy[0].future_config.nested[1].value = "capture mutated"
	_expect(_hidden(CAPTURE.collect(objects, objects.placed)) == expected, "Captured unavailable dictionaries never alias the document")
	objects.placed[0].position.x = 99.0
	await storage.save_named_map()
	_expect(storage.controls.status.text.contains("preserved"), "Save reports preserved unavailable objects")
	# JSON restores integer literals as floats; compare against the same wire representation.
	expected = JSON.parse_string(JSON.stringify(expected))
	var saved: Dictionary = MAP.read(path).get("data", {})
	_expect(_hidden(saved) == expected and saved.objects.size() == 38, "Actual Save Map retains all unavailable records")
	_expect(saved.objects.any(func(record: Dictionary) -> bool: return record.get("object_id") == "shown_0" and record.x == 99.0), "Edits to available objects are saved alongside unavailable records")
	for cycle in 3:
		var loader := LOADER.new(objects)
		var prepared := await loader.prepare_async(saved, self, _progress)
		await loader.clear_async(self, _progress, func() -> bool: return true)
		await loader.commit_async(prepared, self, _progress)
		await storage.snapshot_authored_async(self, _progress, func() -> bool: return true)
		_expect(_hidden(storage.authored_layout) == expected, "Async authored snapshot preserves unavailable records once")
		var active_before: bool = session.active
		session.active = true
		captured = await storage._capture_save()
		session.active = active_before
		_expect(_hidden(captured) == expected, "Save Map/Layout shared active capture preserves records without batch duplication")
		captured.objects[0]["capture_only_edit"] = true
		_expect(not CAPTURE.collect(objects, objects.placed).objects.any(func(record: Dictionary) -> bool: return record.has("capture_only_edit")), "Captured record dictionaries do not alias retained records")
		await storage.save_named_map()
		await storage.save_named_map()
		saved = MAP.read(path).get("data", {})
		_expect(_hidden(saved) == expected and saved.objects.size() == 38, "Repeated load-save never drops or duplicates unavailable records")
	_expect(_hidden(MAP.read(path + ".bak").get("data", {})) == expected, "Backup also retains unavailable records")
	objects.placed[0].position.x += 10.0
	_expect(storage.restore_authored(), "Returning to the authored map restores an available object")
	_expect(_hidden(CAPTURE.collect(objects, objects.placed)) == expected, "Authored restoration preserves unavailable records while reusing other nodes")


func _transactions() -> void:
	var before: Dictionary = CAPTURE.collect(objects, objects.placed)
	var first: Node3D = objects.placed[0]
	var loader := LOADER.new(objects)
	var prepared := loader.prepare({"objects": [{"scene": ASSET}, {"scene": ABSENT, "object_id": "discarded"}]})
	loader._discard(prepared)
	_expect(CAPTURE.collect(objects, objects.placed) == before, "Preparing/discarding another map never replaces retained records")
	var report: Dictionary = objects._apply_layout_data({"objects": [{"scene": ASSET, "scale_x": 0}]})
	_expect(report.has("error") and is_instance_valid(first) and CAPTURE.collect(objects, objects.placed) == before, "Invalid replacement preserves visible and unavailable objects")
	report = objects._apply_layout_data({"objects": [{"scene": ABSENT}]})
	_expect(report.has("error") and CAPTURE.collect(objects, objects.placed) == before, "Existing all-unavailable map rejection remains non-destructive")
	report = await loader.prepare_async(_layout(), self, _progress, func() -> bool: return false)
	_expect(report.has("error") and CAPTURE.collect(objects, objects.placed) == before, "Cancelled preparation preserves current unavailable records")


func _recovery() -> void:
	objects.catalog.available = true
	var saved: Dictionary = MAP.read(path).data
	var report: Dictionary = objects._apply_layout_data(saved)
	_expect(report.get("loaded") == 36 and report.get("skipped") == 2, "A restored model becomes loadable from its preserved record")
	var recovered: Array = objects.placed.filter(func(node: Node3D) -> bool: return str(node.get_meta("planning_object_id", "")) == "recover")
	_expect(recovered.size() == 1 and recovered[0].position == Vector3(4.25, 2.5, -8.0), "Recovered model keeps its ID and authored transform")
	var captured: Dictionary = CAPTURE.collect(objects, objects.placed)
	_expect(captured.objects.size() == 38 and captured.objects.filter(func(record: Dictionary) -> bool: return record.get("object_id") == "recover").size() == 1, "Restored records do not remain as duplicate unavailable objects")


func _clear_and_replace() -> void:
	objects._apply_layout_data({"objects": [{"scene": ASSET}]})
	_expect(CAPTURE.collect(objects, objects.placed).objects.size() == 1, "Another map replaces previous unavailable records")
	objects._apply_layout_data(_layout())
	objects.clear_layout(false, true)
	_expect(CAPTURE.collect(objects, objects.placed).objects.is_empty(), "Explicit clear removes unavailable records too")
	objects._apply_layout_data(_layout())
	objects._apply_layout_data({"objects": []})
	_expect(CAPTURE.collect(objects, objects.placed).objects.is_empty(), "Explicit empty map clears the complete document")


func _progress(_amount: float, _phase: String) -> void: pass


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
