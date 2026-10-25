extends SceneTree
## Entering the planner restores the complete authored TRS, reusing intact nodes.
const OBJECTS := preload("res://game/bootstrap/app/planning_objects.gd")
const STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const ASSET := "res://game/bootstrap/app/tests/fixtures/layout_object.tscn"
const MISSING := "res://missing_authored_transform_model.tscn"
var failures := 0
var world: Node3D
var objects: Node
var storage := STORAGE.new()
var catalog := Catalog.new()

class FixtureObjects extends OBJECTS:
	func _update_status() -> void: pass

class Controls extends Node:
	func _update_history_buttons() -> void: pass

class Catalog extends RefCounted:
	var ENEMY_SCENES: Array = []
	var bind_asset: Callable
	var created := 0
	var rigid := false
	func _migrate_scene_path(path: String) -> String: return path
	func _create_asset(path: String) -> Node3D:
		created += 1
		if not rigid: return (load(path) as PackedScene).instantiate() as Node3D
		var body := RigidBody3D.new()
		body.freeze = true
		return body

class Geometry extends RefCounted:
	func _restore_floor_surface(_node: Node3D, _path: String) -> void: pass


func _initialize() -> void: call_deferred("_run")


func _run() -> void:
	_setup()
	_independent_axes()
	_combined_and_roundtrip()
	_loose_rigid()
	_legacy_defaults()
	_small_jitter()
	_missing_and_extra_nodes()
	world.queue_free()
	await process_frame
	print("Authored transform restore tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _setup() -> void:
	world = Node3D.new()
	root.add_child(world)
	objects = FixtureObjects.new()
	world.add_child(objects)
	var player := Node3D.new()
	world.add_child(player)
	var controls := Controls.new()
	world.add_child(controls)
	var session := {"root": world, "enemies_root": world, "main_player": player, "host": null,
		"active": false, "edit_history": {"stack": []}}
	objects.configure({"session": session, "catalog": catalog, "controls": controls, "geometry": Geometry.new()})
	storage.configure({"session": session, "objects": objects, "controls": controls, "catalog": catalog})
	objects.player_spawn_defined = true
	objects.player_spawn_transform = Transform3D(Basis.IDENTITY, Vector3(8, 1, 9))


func _record() -> Dictionary:
	return {"scene": ASSET, "object_id": "authored", "x": 4.0, "y": 1.5, "z": -3.0,
		"rotation_x": 0.0, "rotation_y": 0.0, "rotation_z": 0.0,
		"scale_x": 1.0, "scale_y": 1.0, "scale_z": 1.0}


func _load(records: Array, rigid: bool = false) -> Node3D:
	catalog.rigid = rigid
	var result: Dictionary = objects._apply_layout_data({"version": 8, "objects": records})
	_expect(not result.has("error"), "Fixture loads through the production map loader")
	storage.snapshot_authored()
	return objects.placed[0]


func _independent_axes() -> void:
	for axis in 3:
		var node := _load([_record()], axis == 1)
		var expected := node.transform
		var angles := node.rotation_degrees
		angles[axis] = 90.0
		node.rotation_degrees = angles
		_verify_restore(node, expected, "rotation axis %d" % axis)
	for axis in 3:
		var node := _load([_record()])
		var expected := node.transform
		var size := node.scale
		size[axis] = 1.75
		node.scale = size
		_verify_restore(node, expected, "scale axis %d" % axis)


func _verify_restore(node: Node3D, expected: Transform3D, label: String) -> void:
	var created := catalog.created
	var before_spawn: Transform3D = objects.player_spawn_transform
	var spawn_defined: bool = objects.player_spawn_defined
	_expect(storage.restore_authored(), "Changed %s triggers authored restoration" % label)
	_expect(is_instance_valid(node) and objects.placed.has(node) and catalog.created == created, "Intact node is reused for %s" % label)
	_expect(is_instance_valid(node) and node.transform.is_equal_approx(expected), "Complete authored transform restored for %s" % label)
	_expect(objects.player_spawn_defined == spawn_defined and objects.player_spawn_transform == before_spawn, "Restoration preserves the player's authored spawn")
	_expect(not storage.restore_authored() and catalog.created == created, "Second restoration is a no-op for %s" % label)


func _combined_and_roundtrip() -> void:
	var record := _record()
	record.merge({"rotation_x": 27.0, "rotation_y": -31.0, "rotation_z": 19.0,
		"scale_x": 1.2, "scale_y": 0.8, "scale_z": 1.6}, true)
	var other := _record()
	other.merge({"object_id": "untouched", "x": 12.0}, true)
	var node := _load([record, other])
	var neighbour: Node3D = objects.placed[1]
	var neighbour_pose := neighbour.transform
	var expected := node.transform
	# Round-trip the real snapshot through JSON, as a saved authored map would be.
	storage.authored_layout = JSON.parse_string(JSON.stringify(storage.authored_layout))
	_expect(not storage.restore_authored(), "JSON numeric roundtrip does not change an unchanged transform")
	node.rotation_degrees = Vector3(72, -31, -24)
	node.scale = Vector3(2.1, 1.3, 0.7)
	_verify_restore(node, expected, "combined tilt/nonuniform scale")
	_expect(is_instance_valid(neighbour) and objects.placed.has(neighbour) and neighbour.transform == neighbour_pose, "Unchanged neighbouring object keeps its node and transform")
	var captured: Dictionary = storage._collect_layout_data()
	var saved: Dictionary = captured.objects.filter(func(row: Dictionary) -> bool: return row.get("object_id") == "authored")[0]
	_expect(is_equal_approx(float(saved.scale_x), 1.2) and is_equal_approx(float(saved.scale_y), 0.8) and is_equal_approx(float(saved.scale_z), 1.6), "Subsequent save captures the restored authored size")


func _loose_rigid() -> void:
	var node := _load([_record()], true) as RigidBody3D
	var expected := node.transform
	node.position += Vector3(1, 0, 0)
	node.rotation_degrees = Vector3(20, 40, 15)
	node.scale = Vector3.ONE * 1.4
	node.linear_velocity = Vector3(1, 2, 3)
	node.angular_velocity = Vector3(2, 1, 3)
	_verify_restore(node, expected, "nearby displaced rigid prop")
	_expect(node.linear_velocity == Vector3.ZERO and node.angular_velocity == Vector3.ZERO, "Reused rigid prop has no residual motion")


func _legacy_defaults() -> void:
	var node := _load([{"scene": ASSET, "object_id": "legacy", "x": 2.0}])
	var expected := node.transform
	# Legacy records may omit all rotation and scale fields.
	storage.authored_layout.version = 1
	for row: Dictionary in storage.authored_layout.objects:
		if row.get("object_id") != "legacy": continue
		for field in ["rotation_x", "rotation_y", "rotation_z", "scale_x", "scale_y", "scale_z"]: row.erase(field)
	node.rotation_degrees.x = 90
	node.scale = Vector3(2, 3, 4)
	_verify_restore(node, expected, "legacy record defaults")


func _small_jitter() -> void:
	var node := _load([_record()])
	var created := catalog.created
	node.position.x += 0.001
	node.rotation_degrees = Vector3.ONE * 0.1
	node.scale = Vector3.ONE * 1.00001
	_expect(not storage.restore_authored() and catalog.created == created, "Sub-quantization pose/scale noise does not rebuild an unchanged map")


func _missing_and_extra_nodes() -> void:
	var missing := {"scene": MISSING, "object_id": "missing", "x": 7.25, "custom": {"keep": [1, 2, 3]}}
	var node := _load([_record(), missing])
	var expected := node.transform
	var extra := Node3D.new()
	world.add_child(extra)
	extra.position = Vector3(50, 1, 50)
	extra.set_meta("planning_scene_path", ASSET)
	extra.set_meta("planning_object_id", "runtime-only")
	objects.placed.append(extra)
	node.rotation_degrees.z = 90
	_verify_restore(node, expected, "partial map with an unavailable model")
	_expect(not is_instance_valid(extra) and objects.placed.size() == 1, "Runtime-only nodes are cleared even when all missing records are unavailable")
	var captured: Dictionary = storage._collect_layout_data()
	_expect(captured.objects.filter(func(row: Dictionary) -> bool: return row.scene == MISSING) == [missing], "Unavailable source record survives complete authored restoration unchanged")
	var current := objects.placed[0] as Node3D
	var rejected: Dictionary = objects._apply_layout_data({"objects": [missing]})
	_expect(rejected.has("error") and is_instance_valid(current), "Explicit load of an entirely unavailable map still preserves the current map")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
