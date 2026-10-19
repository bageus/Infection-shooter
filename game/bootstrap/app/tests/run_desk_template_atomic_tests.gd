extends SceneTree
## A04: malformed or unbuildable templates cannot destroy the current setup.
const FILES := preload("res://game/bootstrap/app/desk_setup_template_files.gd")
const ACTIONS := preload("res://game/bootstrap/app/desk_setup_template_actions.gd")
const SCHEMA := preload("res://game/bootstrap/app/desk_setup_template_schema.gd")
const MODEL := "res://models/objects/enviroments/05/05_computer_mouse.glb"
const PATH := "user://desk_setups/office_desk_2_atomic_regression.json"

class Planner extends RefCounted:
	var root: Node3D
	var placed: Array[Node3D] = []
	var created: Array[WeakRef] = []
	var attempts := 0
	var fail_at := -1
	var without_geometry := false
	func _instantiate_asset(_path: String) -> Node3D:
		attempts += 1
		if attempts == fail_at:
			return null
		var object := Node3D.new()
		if not without_geometry:
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			mesh.mesh.size = Vector3(.1, .05, .1)
			object.add_child(mesh)
		created.append(weakref(object))
		return object

class Mode extends RefCounted:
	var desk: Node3D
	var planner := Planner.new()
	var template_list := OptionButton.new()
	var front_button := Button.new()
	var status := Label.new()
	var zones: Array[Dictionary] = []
	var stations: Array = [{"x": 0.0, "z": 0.0, "grid_height": .89, "usable_width": 2.0, "usable_depth": 2.0}]
	var front := 1
	var zone_index := 0
	var failures: Array[String] = []
	var refreshes := 0
	func _desk_path() -> String:
		return "res://models/objects/enviroments/08/08_office_desk_2.glb"
	func _desk_id() -> String:
		return "existing_desk_id"
	func _attachments() -> Array[Node3D]:
		var result: Array[Node3D] = []
		for item in planner.placed:
			if item.get_meta("planning_attachment", "") == _desk_id():
				result.append(item)
		return result
	func _notify_failure(message: String) -> void:
		failures.append(message)
	func _refresh_zones() -> void:
		refreshes += 1
	func _refresh_zone_items() -> void:
		refreshes += 1

var failures := 0
var stage: Node3D
var mode: Mode
var original: Node3D
var unrelated: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_schema_numbers()
	var bad := _invalid_payloads()
	for payload: Dictionary in bad:
		_start()
		_write_raw(payload)
		var before := original.global_transform
		var zones := mode.zones.duplicate(true)
		_expect(FILES.load(PATH, "office_desk_2").is_empty(), "Invalid nested data is rejected by file loading.")
		ACTIONS.load_selected(mode)
		_unchanged(before, zones)
		await _clear()
	await _test_preparation_failure("late_factory")
	await _test_preparation_failure("no_geometry")
	await _test_preparation_failure("outside_zone")
	await _test_preparation_failure("outside_surface")
	await _test_preparation_failure("world_overflow")
	await _test_preparation_failure("wrong_category")
	await _test_preparation_failure("required_empty")
	await _test_valid_replacement(false)
	await _test_valid_replacement(true)
	await _test_valid_replacement(false, true)
	await _test_empty_replacement()
	await _test_tilt_round_trip()
	_test_save_preserves_valid_file()
	DirAccess.remove_absolute(PATH)
	print("Desk template atomic tests: %d failures (%d invalid payloads)" % [failures, bad.size()])
	quit(1 if failures > 0 else 0)


func _payload() -> Dictionary:
	return {"version": 1, "desk": "office_desk_2", "front": 0,
		"zones": [{"name": "Mouse", "category": "Mouse", "required": false, "angle": 0.0, "x": 0.0, "z": 0.0, "width": 1.0, "depth": 1.0, "height": .89, "floor": false}],
		"items": [{"path": MODEL, "zone": 0, "x": .1, "y": .89, "z": -.1, "yaw": .4}]}


func _invalid_payloads() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for field in ["zones", "items"]:
		for value in ["invalid", {}, null, ["invalid"]]:
			var data := _payload()
			data[field] = value
			result.append(data)
		var missing := _payload()
		missing.erase(field)
		result.append(missing)
	for field in ["x", "z", "width", "depth", "height", "floor"]:
		var data := _payload()
		data.zones[0].erase(field)
		result.append(data)
	for change in [{"width": 0}, {"depth": -1}, {"x": "0"}, {"floor": 1}, {"floor": true, "height": .89}, {"angle": "bad"}, {"required": "false"}, {"category": []}]:
		var data := _payload()
		data.zones[0].merge(change, true)
		result.append(data)
	for change in [{"zone": 20}, {"zone": .5}, {"x": "0"}, {"y": null}, {"yaw": "bad"}, {"path": "res://models/objects/enviroments/05/missing.glb"}, {"path": "res://project.godot"}, {"path": "res://models/objects/enviroments/../../project.godot"}]:
		var data := _payload()
		data.items[0].merge(change, true)
		result.append(data)
	for field in ["path", "x", "y", "z"]:
		var data := _payload()
		data.items[0].erase(field)
		result.append(data)
	for change in [{"front": 2}, {"front": "1"}, {"version": true}, {"desk": "another_desk"}]:
		var data := _payload()
		data.merge(change, true)
		result.append(data)
	return result


func _test_schema_numbers() -> void:
	for value in [NAN, INF, -INF, 1e100, true]:
		var data := _payload()
		data.items[0].x = value
		_expect(not SCHEMA.valid(data, "office_desk_2"), "Unsafe coordinates cannot reach scene transforms.")


func _start() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	mode = Mode.new()
	mode.planner.root = stage
	mode.desk = Node3D.new()
	stage.add_child(mode.desk)
	mode.desk.position = Vector3(3, 0, 4)
	mode.desk.rotation.y = .7
	mode.zones.assign(_payload().zones)
	mode.front_button.text = "Old front"
	mode.status.text = "Old status"
	original = Node3D.new()
	stage.add_child(original)
	original.position = Vector3(1, 2, 3)
	original.set_meta("planning_attachment", "existing_desk_id")
	original.set_meta("untouched", "original")
	unrelated = Node3D.new()
	stage.add_child(unrelated)
	mode.planner.placed.assign([original, unrelated])
	mode.template_list.add_item("atomic_regression")
	mode.template_list.set_item_metadata(0, PATH)
	mode.template_list.select(0)


func _test_preparation_failure(kind: String) -> void:
	_start()
	var data := _payload()
	if kind == "late_factory":
		data.items.append(data.items[0].duplicate())
		mode.planner.fail_at = 2
	elif kind == "no_geometry":
		mode.planner.without_geometry = true
	elif kind == "outside_zone":
		data.items[0].x = 2.0
	elif kind == "outside_surface":
		data.zones[0].x = 20.0
	elif kind == "world_overflow":
		mode.desk.scale = Vector3.ONE * 1e20
		data.items[0].x = 1e30
	elif kind == "wrong_category":
		data.zones[0].category = "Keyboard"
	elif kind == "required_empty":
		data.zones[0].required = true
		data.items.clear()
	_expect(FILES.save("office_desk_2", "atomic_regression", data), "Structurally valid fixture is written.")
	var before := original.global_transform
	var zones := mode.zones.duplicate(true)
	ACTIONS.load_selected(mode)
	_unchanged(before, zones)
	for created in mode.planner.created:
		_expect(created.get_ref() == null, "Aborted preparation releases every temporary model.")
	await _clear()


func _unchanged(before: Transform3D, zones: Array) -> void:
	_expect(not original.is_queued_for_deletion() and original.global_transform.is_equal_approx(before), "The original object and transform survive refusal.")
	_expect(mode.planner.placed == [original, unrelated], "Placed list and unrelated objects survive refusal.")
	_expect(mode.zones == zones and mode.front == 1 and mode.zone_index == 0, "Zones, front and selection survive refusal.")
	_expect(mode.front_button.text == "Old front" and mode.refreshes == 0, "Failed import does not redraw a partial setup.")
	_expect(mode.failures.size() == 1 and not mode.status.text.begins_with("Template applied"), "Refusal is reported without a success message.")
	_expect(original.get_meta("untouched") == "original", "Existing metadata is preserved.")
	_expect(stage.get_child_count() == 3, "No temporary staging root survives refusal.")


func _test_valid_replacement(legacy: bool, floor_zone: bool = false) -> void:
	_start()
	var data := _payload()
	if floor_zone:
		data.zones[0].floor = true
		data.zones[0].height = 0.0
		data.items[0].y = 0.0
	if legacy:
		for field in ["name", "required", "angle", "category"]:
			data.zones[0].erase(field)
		data.erase("front")
		data.items[0].erase("zone")
		data.items[0].erase("yaw")
	_expect(FILES.save("office_desk_2", "atomic_regression", data), "Valid v1 template saves, including legacy defaults.")
	ACTIONS.load_selected(mode)
	_expect(mode.failures.is_empty(), "Valid prepared composition applies completely.")
	_expect(original.is_queued_for_deletion() and mode.planner.placed.size() == 2 and mode.planner.placed.has(unrelated), "Only the current desk's attachments are replaced.")
	var object: Node3D = mode.planner.placed.back()
	_expect(object.global_position.distance_to(mode.desk.to_global(Vector3(.1, float(data.items[0].y), -.1))) < .001, "Replacement uses the translated and rotated desk's local coordinates.")
	_expect(object.get_meta("planning_attachment", "") == "existing_desk_id" and object.get_meta("planning_zone", -1) == 0, "Replacement metadata is complete.")
	_expect(object.get_parent() == stage and object.can_process(), "Committed objects leave disabled staging and resume normal processing.")
	_expect(mode.status.text.begins_with("Template applied"), "Only committed replacements report success.")
	await _clear()


func _test_empty_replacement() -> void:
	_start()
	_expect(FILES.save("office_desk_2", "atomic_regression", {"version": 1, "desk": "office_desk_2", "zones": [], "items": []}), "An explicitly empty template remains valid.")
	ACTIONS.load_selected(mode)
	_expect(mode.failures.is_empty() and original.is_queued_for_deletion(), "Empty template intentionally clears this desk.")
	_expect(mode.zones.is_empty() and mode.zone_index == -1 and mode.planner.placed == [unrelated], "Intentional clearing preserves unrelated objects.")
	await _clear()


## A laid item keeps its tilt and yaw through save, file load and preparation.
func _test_tilt_round_trip() -> void:
	_start()
	var data := _payload()
	data.items[0].merge({"tilt_x": 1.2, "tilt_z": -0.6}, true)
	_expect(SCHEMA.valid(data, "office_desk_2"), "Tilt angles are valid template item data.")
	var bad := _payload()
	bad.items[0].tilt_z = "bad"
	_expect(not SCHEMA.valid(bad, "office_desk_2"), "Non-numeric tilt is refused.")
	_expect(FILES.save("office_desk_2", "atomic_regression", data), "Tilted template is written.")
	var saved := FILES.load(PATH, "office_desk_2")
	_expect(not saved.is_empty() and is_equal_approx(float(saved.items[0].tilt_x), 1.2) and is_equal_approx(float(saved.items[0].tilt_z), -0.6), "Saved tilt is read back from the template file.")
	var prepared := ACTIONS._prepare(mode, saved)
	_expect(not prepared.is_empty(), "Tilted template is prepared for placement.")
	if not prepared.is_empty():
		var object: Node3D = prepared.items[0]
		_expect(is_equal_approx(object.rotation.x, 1.2) and is_equal_approx(object.rotation.z, -0.6), "Loaded template restores the saved lay.")
		_expect(is_equal_approx(object.rotation.y, mode.desk.rotation.y + .4), "Loaded lay keeps the saved yaw relative to the desk.")
	await _clear()


func _test_save_preserves_valid_file() -> void:
	_expect(FILES.save("office_desk_2", "atomic_regression", _payload()), "Baseline valid save succeeds.")
	var bytes := FileAccess.get_file_as_bytes(PATH)
	var bad := _payload()
	bad.zones = ["invalid-zone"]
	_expect(not FILES.save("office_desk_2", "atomic_regression", bad), "Malformed save is refused.")
	_expect(FileAccess.get_file_as_bytes(PATH) == bytes, "Refused save keeps the previous file byte-for-byte.")
	_expect(FILES.load("user://desk_setups/office_desk_2_../bad.json", "office_desk_2").is_empty(), "Template paths cannot traverse folders.")


func _write_raw(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FILES.ROOT))
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _clear() -> void:
	mode.template_list.free()
	mode.front_button.free()
	mode.status.free()
	stage.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
