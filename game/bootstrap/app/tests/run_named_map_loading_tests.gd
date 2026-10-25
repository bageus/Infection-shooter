extends SceneTree
const BLOOD := preload("res://game/bootstrap/app/planning_blood_placement.gd")
const STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const OBJECTS := preload("res://game/bootstrap/app/planning_objects.gd")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const HISTORY := preload("res://game/bootstrap/app/planning_edit_history.gd")
const ASSET := "res://game/bootstrap/app/tests/fixtures/layout_object.tscn"
const INVALID := "res://game/bootstrap/app/tests/fixtures/invalid_layout_object.tscn"
const PLAYER := "res://game/features/player/public/player.tscn"
var failures := 0
var heartbeat := 0
var files: Array[String] = []

class Session extends Node3D:
	var ui := Control.new()
	var root := Node3D.new()
	var enemies_root := Node3D.new()
	var main_player := Node3D.new()
	var edit_history := HISTORY.new()
	var active := true

class Controls extends Node:
	var hud_layout := preload("res://game/bootstrap/app/planning_hud_layout.gd").new()
	var status := Label.new()
	func _update_history_buttons() -> void:
		pass

class Geometry extends RefCounted:
	func _restore_floor_surface(_node: Node3D, _path: String) -> void:
		pass

class TrackingStorage extends STORAGE:
	var on_snapshot: Callable
	func snapshot_authored_async(tree: SceneTree, progress: Callable, alive: Callable) -> bool:
		if on_snapshot.is_valid():
			on_snapshot.call()
		return await super.snapshot_authored_async(tree, progress, alive)

class Mark extends Node3D:
	var config := {"owner": "duplicate", "mesh": "Anchor"}
	var attached: Node3D
	func get_blood_attachment() -> Dictionary:
		return config
	func attach_blood(anchor: Node3D, _id: String) -> void:
		attached = anchor

class TrackingCatalog extends CATALOG:
	var staged: Array[WeakRef] = []
	var after_create: Callable
	func _create_asset(path: String) -> Node3D:
		var node := super._create_asset(path)
		if node != null:
			staged.append(weakref(node))
			if after_create.is_valid():
				after_create.call(staged.size())
		return node


func _initialize() -> void:
	process_frame.connect(func() -> void: heartbeat += 1)
	call_deferred("_run")


func _fixture() -> Variant:
	var session := Session.new()
	session.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(session)
	for child in [session.ui, session.root, session.enemies_root, session.main_player]:
		session.add_child(child)
	var controls := Controls.new()
	controls.add_child(controls.status)
	session.add_child(controls)
	var objects := OBJECTS.new()
	session.add_child(objects)
	var catalog := TrackingCatalog.new()
	objects.configure({"session": session, "catalog": catalog, "controls": controls, "geometry": Geometry.new()})
	var storage := TrackingStorage.new()
	storage.configure({"session": session, "objects": objects, "controls": controls, "catalog": catalog})
	storage.map_name_edit = LineEdit.new()
	session.ui.add_child(storage.map_name_edit)
	storage.map_name_edit.text = "old_name"
	var original := Node3D.new()
	session.root.add_child(original)
	objects.placed.append(original)
	objects.selected = original
	session.main_player.position = Vector3(3, 4, 5)
	objects.player_spawn_defined = true
	objects.player_spawn_transform = session.main_player.transform
	session.edit_history.stack.append({"kind": "sentinel"})
	storage.authored_layout = {"sentinel": true}
	return storage


func _write(storage: Variant, name: String, records: Array) -> String:
	storage._ensure_maps_dir()
	var path: String = storage._map_path(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 8, "objects": records}))
	file.close()
	files.append(path)
	return path


func _run() -> void:
	paused = true
	await _attachments()
	await _errors()
	await _replacement()
	await _teardown(false)
	await _teardown(true)
	await _teardown_free()
	await _teardown_snapshot()
	for path in files:
		DirAccess.remove_absolute(path)
	paused = false
	print("Named map loading tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _errors() -> void:
	var storage: Variant = _fixture()
	var original: Node3D = storage.objects.placed[0]
	var cases: Array[Array] = [[{"scene": ASSET, "scale_x": 0}], [{"scene": "res://missing_named_map.tscn"}], _records(64) + [{"scene": INVALID}]]
	for records in cases:
		_write(storage, "bad", records)
		await storage.load_named_map("bad")
		_expect(is_instance_valid(original) and storage.objects.placed == [original], "Preparation failure preserves old map")
		_expect(storage.objects.selected == original and storage.session.edit_history.stack.size() == 1, "Failure preserves selection and history")
		_expect(storage.session.main_player.position == Vector3(3, 4, 5), "Failure preserves spawn")
		_expect(storage.authored_layout == {"sentinel": true} and storage.map_name_edit.text == "old_name", "Failure preserves authored snapshot and map name")
		_expect(not storage.map_loading and storage.session.ui.process_mode == Node.PROCESS_MODE_INHERIT, "Failure unlocks UI")
		for staged in storage.catalog.staged:
			_expect(staged.get_ref() == null, "Failed preparation frees every staged node")
	var path := _write(storage, "broken", [])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{")
	file.close()
	await storage.load_named_map("broken")
	await storage.load_named_map("absent")
	_expect(is_instance_valid(original), "Malformed/missing file preserves map")
	storage.session.queue_free()
	await process_frame


func _replacement() -> void:
	var storage: Variant = _fixture()
	var session: Node = storage.session
	var original: Node = storage.objects.placed[0]
	# Exercise staged removal too, including invalid and retained entries.
	for index in 64:
		var old := Node3D.new()
		session.root.add_child(old)
		storage.objects.placed.append(old)
	var retained := Node3D.new()
	session.root.add_child(retained)
	retained.set_meta("planning_existing", true)
	storage.objects.placed.append(retained)
	var deleted := Node3D.new()
	storage.objects.placed.append(deleted)
	deleted.free()
	var records := _records(64)
	records.append({"scene": PLAYER, "x": 11})
	records.append({"scene": "res://missing_named_map.tscn"})
	var path := _write(storage, "replacement", records)
	var saved := FileAccess.get_file_as_string(path)
	var start := heartbeat
	storage.load_named_map("replacement")
	_expect(storage.map_loading and is_instance_valid(original), "Named load starts asynchronously and retains old map")
	storage.save_named_map()
	storage.save_layout()
	storage.load_named_map("absent")
	while storage.map_loading:
		_expect(paused, "Gameplay remains paused throughout transaction")
		await process_frame
	_expect(heartbeat - start >= 12, "Read/prepare/free/commit yield over multiple frames")
	_expect(not is_instance_valid(original) and storage.objects.placed.size() == 65, "Replacement frees old nodes and keeps protected node")
	_expect(storage.objects.placed[0] == retained and storage.objects.placed[-1].position.x == 63, "Retained nodes and record ordering survive")
	_expect(session.main_player.position.x == 11 and session.edit_history.stack.is_empty(), "Successful commit restores spawn and resets history")
	_expect(storage.map_name_edit.text == "replacement" and storage.authored_layout == storage._collect_layout_data(), "Snapshot/name update only after success")
	_expect(storage.controls.status.text.contains("1 missing object(s) skipped"), "Missing objects retain legacy report")
	_expect(FileAccess.get_file_as_string(path) == saved and not FileAccess.file_exists(storage._map_path("old_name")), "Busy commands cannot save partial maps")
	_write(storage, "empty", [])
	await storage.load_named_map("empty")
	_expect(storage.objects.placed == [retained], "Explicit empty map keeps legacy retained-node behavior")
	session.queue_free()
	await process_frame


func _teardown(during_commit: bool) -> void:
	var storage: Variant = _fixture()
	var catalog: TrackingCatalog = storage.catalog
	var owner: Node = storage.session
	_write(storage, "depart", _records(64))
	if during_commit:
		catalog.bind_asset = func(_node: Node3D) -> void:
			if storage.objects.placed.size() == 17:
				owner.queue_free()
	else:
		catalog.after_create = func(count: int) -> void:
			if count == 17:
				owner.queue_free()
	await storage.load_named_map("depart")
	await process_frame
	_expect(not storage.map_loading and not is_instance_valid(owner), "Departed owner cancels suspended load")
	for staged in catalog.staged:
		_expect(staged.get_ref() == null, "Teardown releases staged/committed nodes")
	catalog.bind_asset = Callable()
	catalog.after_create = Callable()


func _teardown_free() -> void:
	var storage: Variant = _fixture()
	var owner: Node = storage.session
	var catalog: TrackingCatalog = storage.catalog
	for index in 64:
		var old := Node3D.new()
		owner.root.add_child(old)
		storage.objects.placed.append(old)
	_write(storage, "depart_free", _records(64))
	var observer := func() -> void:
		if is_instance_valid(owner) and catalog.staged.size() == 64:
			if not is_instance_valid(storage.objects.placed[0]):
				owner.queue_free()
	process_frame.connect(observer)
	await storage.load_named_map("depart_free")
	process_frame.disconnect(observer)
	await process_frame
	_expect(not storage.map_loading and not is_instance_valid(owner), "Teardown during old-map removal cancels commit")
	for staged in catalog.staged:
		_expect(staged.get_ref() == null, "Removal cancellation frees prepared nodes")


func _teardown_snapshot() -> void:
	var storage: Variant = _fixture()
	var owner: Node = storage.session
	storage.on_snapshot = func() -> void: owner.queue_free()
	_write(storage, "depart_snapshot", _records(64))
	await storage.load_named_map("depart_snapshot")
	await process_frame
	_expect(not storage.map_loading and not is_instance_valid(owner), "Snapshot teardown releases loading lock")
	_expect(storage.authored_layout == {"sentinel": true}, "Cancelled snapshot never publishes partial data")
	storage.on_snapshot = Callable()


func _attachments() -> void:
	var branch := Node3D.new()
	root.add_child(branch)
	var mark := Mark.new()
	branch.add_child(mark)
	var expected: Node3D
	for index in 130:
		var owner := Node3D.new()
		branch.add_child(owner)
		owner.set_meta("planning_object_id", "duplicate")
		var anchor := Node3D.new()
		anchor.name = "Anchor"
		owner.add_child(anchor)
		expected = anchor
	BLOOD.restore_attachments([branch])
	_expect(mark.attached == expected, "Synchronous duplicate ids resolve in preorder")
	mark.attached = null
	var start := heartbeat
	_expect(await BLOOD.restore_attachments_async([branch], self, func() -> bool: return true), "Staged attachment scan completes")
	_expect(mark.attached == expected and heartbeat > start, "Staged scan preserves duplicate-id resolution and yields")
	mark.config.owner = "missing"
	mark.attached = null
	await BLOOD.restore_attachments_async([branch], self, func() -> bool: return true)
	_expect(mark.attached == null, "Missing blood owner remains unattached")
	branch.queue_free()
	await process_frame


func _records(count: int) -> Array:
	var records: Array = []
	for index in count:
		records.append({"scene": ASSET, "x": index})
	return records


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
