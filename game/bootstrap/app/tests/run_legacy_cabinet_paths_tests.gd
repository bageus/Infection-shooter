extends SceneTree
## Real map load/save/load preserves the four historical cabinet scene contracts.
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const OBJECTS := preload("res://game/bootstrap/app/planning_objects.gd")
const LOADER := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const CAPTURE := preload("res://game/bootstrap/app/planning_layout_capture.gd")
const MAP := preload("res://game/bootstrap/app/planning_map_file.gd")
const PREFIX := "res://game/presentation/office_floor/public/props/"
const FILE := "user://legacy_cabinet_round_trip.json"
const CASES := [
	["03_drawer_cabinet.tscn", "res://models/objects/03_drawer_cabinet.glb", 18.0, .75, 1.5],
	["03_drawer_cabinet_mobile.tscn", "res://models/objects/03_drawer_cabinet.glb", 14.0, .9, 1.8],
	["03_file_cabinet_tall.tscn", "res://models/objects/03_file_cabinet_tall.glb", 55.0, .25, .45],
	["03_locker_tall.tscn", "res://models/objects/enviroments/03/03_locker_tall_dented.glb", 55.0, .25, .45],
]
class Controls extends Node:
	var hud_layout := preload("res://game/bootstrap/app/planning_hud_layout.gd").new()
	var status := Label.new()
	func _update_history_buttons() -> void:
		pass
class Geometry extends RefCounted:
	func _restore_floor_surface(_node: Node3D, _path: String) -> void:
		pass
var failures := 0
var world: Node3D
var objects: Node
var catalog := CATALOG.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_setup()
	_catalog_contract()
	for index in CASES.size():
		await _round_trip([_record(index)], false)
	var mixed: Array = []
	for index in CASES.size():
		mixed.append(_record(index))
	mixed.append({"scene": PREFIX + "07_table.tscn", "x": 30, "object_id": "unchanged_table"})
	await _round_trip(mixed, true)
	await _unknown_paths()
	world.queue_free()
	for frame in 3:
		await process_frame
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(FILE + suffix):
			DirAccess.remove_absolute(FILE + suffix)
	print("Legacy cabinet paths tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _setup() -> void:
	world = Node3D.new()
	# Keep fixture bodies still while deferred builders create the real shapes.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(world)
	var player := Node3D.new()
	world.add_child(player)
	var controls := Controls.new()
	controls.add_child(controls.status)
	world.add_child(controls)
	objects = OBJECTS.new()
	world.add_child(objects)
	catalog._build_environment_catalogs()
	objects.configure({"session": {"root": world, "enemies_root": world,
		"main_player": player, "edit_history": {"stack": []}, "active": false},
		"catalog": catalog, "controls": controls, "geometry": Geometry.new()})


func _catalog_contract() -> void:
	for entry: Array in CASES:
		var path: String = PREFIX + str(entry[0])
		_expect(catalog._migrate_scene_path(path) == path, "Historical scene identity: " + path)
	_expect(catalog._migrate_scene_path(PREFIX + "06_office_chair.tscn") == "res://models/objects/enviroments/06/06_office_chair.glb", "Existing chair migration unchanged")
	_expect(catalog._migrate_scene_path(PREFIX + "11_plant_large.tscn") == "res://models/objects/enviroments/11/11_plant_large.glb", "Existing plant migration unchanged")
	_expect(catalog._migrate_scene_path(PREFIX + "not_a_known_prop.tscn").is_empty(), "Unknown legacy prop is not blanket-restored")
	_expect(catalog._migrate_scene_path("res://models/objects/Office_Set/old.glb").is_empty(), "Retired Office_Set remains retired")


func _record(index: int) -> Dictionary:
	return {"scene": PREFIX + str(CASES[index][0]), "x": index * 6.0 + .25,
		"y": 1.5 + index * .2, "z": -3.5, "rotation_x": 5.0, "rotation_y": 17.0 + index * 23,
		"rotation_z": -3.0, "scale_x": 1.1, "scale_y": .8, "scale_z": 1.3,
		"object_id": "cabinet_%d" % index, "desk_id": "desk_%d" % index,
		"attachment": "parent_%d" % index, "zone": index, "auto_fixture": "legacy-marker"}


func _round_trip(records: Array, asynchronous: bool) -> void:
	var data := {"version": 8, "objects": records}
	var report := await _apply(data, asynchronous)
	_expect(not report.has("error") and report.get("loaded", 0) == records.size() and report.get("skipped", -1) == 0, "All cabinet records load (async=%s)" % asynchronous)
	if report.has("error") or objects.placed.size() != records.size():
		return
	for frame in 2:
		await process_frame
	_verify_nodes(records)
	var saved: Dictionary = CAPTURE.collect(objects, objects.placed)
	_expect(saved.objects.size() == records.size(), "Capture keeps every record")
	_expect(not MAP.write(FILE, saved).has("error"), "Map file is written and verified")
	var read: Dictionary = MAP.read(FILE)
	_expect(not read.has("error"), "Map file reload succeeds")
	if read.has("error"):
		return
	report = await _apply(read.data, asynchronous)
	_expect(not report.has("error") and report.get("loaded", 0) == records.size() and report.get("skipped", -1) == 0, "Saved paths reload without skipping")
	if report.has("error") or objects.placed.size() != records.size():
		return
	for frame in 2:
		await process_frame
	_verify_nodes(records)
	var resaved: Dictionary = CAPTURE.collect(objects, objects.placed)
	_verify_saved(saved, resaved)


func _apply(data: Dictionary, asynchronous: bool) -> Dictionary:
	if not asynchronous:
		return objects._apply_layout_data(data)
	var loader := LOADER.new(objects)
	var progress := func(_value: float, _phase: String) -> void: pass
	var prepared: Dictionary = await loader.prepare_async(data, self, progress)
	if prepared.has("error"):
		return prepared
	return await loader.commit_async(prepared, self, progress)


func _verify_nodes(records: Array) -> void:
	for index in records.size():
		var node: Node3D = objects.placed[index]
		var record: Dictionary = records[index]
		_expect(node.scene_file_path == record.scene and node.get_meta("planning_scene_path") == record.scene, "Exact PackedScene identity persists")
		var angles := Vector3(float(record.get("rotation_x", 0)), float(record.get("rotation_y", 0)), float(record.get("rotation_z", 0))) * PI / 180.0
		var scale := Vector3(float(record.get("scale_x", 1)), float(record.get("scale_y", 1)), float(record.get("scale_z", 1)))
		var position := Vector3(float(record.get("x", 0)), float(record.get("y", 0)), float(record.get("z", 0)))
		var expected := Transform3D(Basis.from_euler(angles) * Basis.from_scale(scale), position)
		_expect(node.transform.is_equal_approx(expected), "Position, all rotations and nonuniform scale preserved")
		_expect(node.get_meta("planning_object_id") == record.object_id, "Object identity survives save/reload")
		for entry: Array in CASES:
			if record.scene == PREFIX + str(entry[0]):
				_verify_cabinet(node, entry, record)


func _verify_saved(first: Dictionary, second: Dictionary) -> void:
	_expect(first.version == second.version and first.objects.size() == second.objects.size(), "DTO version/count preserved")
	for index in first.objects.size():
		var a: Dictionary = first.objects[index]
		var b: Dictionary = second.objects[index]
		_expect(a.size() == b.size(), "Same optional DTO fields")
		for field in a:
			_expect(b.has(field), "Saved field survives: " + str(field))
			if not b.has(field):
				continue
			if a[field] is float or a[field] is int:
				# Euler recomposition/JSON use floating point; 0.0001 units/degrees
				# distinguishes numeric round-off from a changed authored transform.
				_expect(absf(float(a[field]) - float(b[field])) < .0001, "Numeric field round trip: " + str(field))
			else:
				_expect(a[field] == b[field], "Exact path/metadata round trip: " + str(field))


func _verify_cabinet(node: Node3D, entry: Array, record: Dictionary) -> void:
	_expect(node.get_meta("planning_desk_id") == record.desk_id and node.get_meta("planning_attachment") == record.attachment, "Attachment/desk links preserved")
	_expect(node.get_meta("planning_zone") == record.zone and node.get_meta("planning_auto_fixture") == record.auto_fixture, "Zone/fixture metadata preserved")
	var visual := node.find_child("Visual", true, false) as Node3D
	_expect(visual != null and visual.scene_file_path == entry[1], "Original visual model kept")
	var body := node.get_node("Body") as RigidBody3D
	_expect(body != null, "Original rigid body kept")
	if body != null:
		_expect(is_equal_approx(body.mass, entry[2]) and is_equal_approx(body.bullet_impulse, entry[3]) and is_equal_approx(body.character_push_impulse, entry[4]), "Distinct authored mass/push parameters kept")
		var authored: Node = (load(PREFIX + str(entry[0])) as PackedScene).instantiate()
		_expect(body.get_script() == authored.get_node("Body").get_script(), "Authored public scene body script kept")
		authored.free()
		_expect(not body.find_children("*", "CollisionShape3D", true, false).is_empty(), "Real deferred collision builder ran")


func _unknown_paths() -> void:
	var record := _record(0)
	var data := {"version": 8, "objects": [record, {"scene": PREFIX + "not_a_known_prop.tscn"}]}
	var report: Dictionary = objects._apply_layout_data(data)
	_expect(not report.has("error") and report.get("loaded", 0) == 1 and report.get("skipped", 0) == 1, "Mixed map skips only the genuinely unknown path")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
