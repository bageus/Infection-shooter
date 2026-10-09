extends SceneTree
const OBJECTS := preload("res://game/bootstrap/app/planning_objects.gd")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const LOADER := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const HISTORY := preload("res://game/bootstrap/app/planning_edit_history.gd")
const STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const ASSET := "res://game/bootstrap/app/tests/fixtures/layout_object.tscn"
const INVALID := "res://game/bootstrap/app/tests/fixtures/invalid_layout_object.tscn"
const PLAYER := "res://game/features/player/public/player.tscn"
var failures := 0

class Controls extends Node:
	var status := Label.new()
	func _update_history_buttons() -> void:
		pass

class Geometry extends RefCounted:
	func _restore_floor_surface(_node: Node3D, _path: String) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player := Node3D.new()
	world.add_child(player)
	player.position = Vector3(3, 4, 5)
	var controls := Controls.new()
	controls.add_child(controls.status)
	world.add_child(controls)
	var objects := OBJECTS.new()
	world.add_child(objects)
	var history := HISTORY.new()
	var session := {"root": world, "enemies_root": world, "main_player": player, "edit_history": history, "active": false}
	objects.configure({"session": session, "catalog": CATALOG.new(), "controls": controls, "geometry": Geometry.new()})
	var original := Node3D.new()
	world.add_child(original)
	objects.placed.append(original)
	objects.selected = original
	objects.player_spawn_defined = true
	objects.player_spawn_transform = player.transform
	history.stack.append({"kind": "sentinel"})
	var invalid_maps: Array[Dictionary] = [
		{}, {"objects": {}}, {"objects": null}, {"objects": [42]},
		{"version": 99, "objects": []}, {"version": "8", "objects": []},
		{"objects": [{}]}, {"objects": [{"scene": 42}]},
		{"objects": [{"scene": ASSET, "x": "oops"}]},
		{"objects": [{"scene": ASSET, "z": INF}]},
		{"objects": [{"scene": ASSET, "scale_y": 0}]},
		{"objects": [{"scene": ASSET, "light_color": [1]}]},
		{"objects": [{"scene": ASSET, "blood_normal": [0, "x", 1]}]},
		{"objects": [{"scene": ASSET, "display": []}]},
		{"objects": [{"scene": ASSET}, {"scene": INVALID}]},
		{"objects": [{"scene": "res://missing_layout_scene.tscn"}]},
	]
	for data: Dictionary in invalid_maps:
		var report: Dictionary = objects._apply_layout_data(data)
		_expect(report.has("error"), "Invalid replacement rejected")
		_expect(is_instance_valid(original) and objects.placed == [original], "Current layout remains intact")
		_expect(objects.selected == original and history.stack.size() == 1, "Selection and undo remain intact")
		_expect(player.position == Vector3(3, 4, 5) and objects.player_spawn_transform == player.transform, "Player spawn remains intact")
	var storage := STORAGE.new()
	storage.objects = objects
	var path := "user://invalid_layout_loading_test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"objects": "wrong"}')
	file.close()
	_expect(storage._load_layout_from_path(path).has("error") and is_instance_valid(original), "File loading validates before clearing")
	DirAccess.remove_absolute(path)
	var mixed := {"version": 8, "objects": [{"scene": ASSET, "x": 7}, {"scene": "res://missing_layout_scene.tscn"}, {"scene": PLAYER, "x": 11}]}
	var report: Dictionary = objects._apply_layout_data(mixed)
	_expect(report.loaded == 1 and report.skipped == 1, "Valid records load; missing assets retain legacy skip report")
	_expect(not is_instance_valid(original) and history.stack.is_empty(), "Successful commit replaces old layout and undo (old valid=%s, undo=%s)" % [is_instance_valid(original), history.stack])
	_expect(objects.placed[0].position.x == 7 and player.position.x == 11, "Object and player transforms restored")
	var records: Array = []
	for index in 64:
		records.append({"scene": ASSET, "x": index})
	var loader := LOADER.new(objects)
	var frame := Engine.get_process_frames()
	var prepared := await loader.prepare_async({"objects": records}, self, func(_value: float, _phase: String) -> void: pass)
	_expect(Engine.get_process_frames() - frame >= 4 and objects.placed.size() == 1, "Async preparation yields while retaining current layout")
	frame = Engine.get_process_frames()
	report = await loader.commit_async(prepared, self, func(_value: float, _phase: String) -> void: pass)
	_expect(Engine.get_process_frames() - frame >= 4 and report.loaded == 64, "Async commit builds the layout over multiple frames")
	_expect(objects.placed[63].position.x == 63, "Async commit retains record order")
	_expect(not objects._apply_layout_data({"objects": []}).has("error") and objects.placed.is_empty(), "Explicit empty map is a valid clear operation")
	world.queue_free()
	await process_frame
	print("Layout loading tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
