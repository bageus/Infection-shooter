extends SceneTree
const SETTLE := preload("res://game/bootstrap/app/planning_settle.gd")
const STABILITY := preload("res://game/bootstrap/app/planning_stability.gd")
const PHYSICS := preload("res://game/bootstrap/app/planning_physics.gd")
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
const HUNGER := preload("res://game/features/infected/public/decor/corpse_hunger.tscn")
const PART := preload("res://game/features/infected/public/decor/part_horde_tentacle.tscn")
var failures := 0

class Controls extends Node:
	var hud_layout := preload("res://game/bootstrap/app/planning_hud_layout.gd").new()
	var status := Label.new()
	func _update_history_buttons() -> void:
		pass

class Geometry extends RefCounted:
	func _restore_floor_surface(_node: Node3D, _path: String) -> void:
		pass
	func _combined_aabb(_node: Node3D, _ignore_selection: bool) -> AABB:
		return AABB(Vector3.ONE * -0.5, Vector3.ONE)

class WarningObjects extends Node:
	var placed: Array[Node3D] = []
	var selected: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	stage.add_child(floor_body)
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(30, 0.2, 30)
	floor_body.position.y = -0.1
	floor_body.add_child(floor_shape)
	var box := RigidBody3D.new()
	box.position = Vector3(4, 2, 0)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	box.add_child(shape)
	stage.add_child(box)
	var corpse := HUNGER.instantiate() as Node3D
	corpse.call("configure_decor_pose", {"seed": 9, "pose": "seated", "facing": 0.3})
	corpse.position = Vector3(0, 1, 0)
	stage.add_child(corpse)
	var part := PART.instantiate() as RigidBody3D
	part.position = Vector3(-4, 0, 0)
	stage.add_child(part)
	var mutilated := (load("res://game/features/infected/public/decor/corpse_hunger_mutilated.tscn") as PackedScene).instantiate() as Node3D
	mutilated.position = Vector3(5, 0, 5)
	stage.add_child(mutilated)
	await physics_frame
	_check(STABILITY.may_move(box, AABB(Vector3.ONE * -0.5, Vector3.ONE)), "Floating body is red")
	paused = true
	var label := Label.new()
	stage.add_child(label)
	var job := SETTLE.new()
	_check(await job.run(stage, [box, corpse, part, mutilated], label), "Save prepares stable physics: " + label.text)
	_check(paused, "Gameplay remains paused")
	_check(box.position.y < 0.55 and box.position.y > 0.45, "Body rests on real floor")
	_check(part.position.y > -0.1, "Embedded small part does not fall through floor")
	_check(not STABILITY.may_move(box, AABB(Vector3.ONE * -0.5, Vector3.ONE)), "Supported body clears warning")
	var pose: Dictionary = corpse.call("get_decor_pose")
	_check(pose.has("physics_v1"), "Final bones are serialized")
	var saved_pose: Dictionary = JSON.parse_string(JSON.stringify(pose))
	var mutilated_pose: Dictionary = JSON.parse_string(JSON.stringify(mutilated.call("get_decor_pose")))
	_check(VALIDATOR.error({"objects": [{"scene": "res://corpse.tscn", "decor_pose": mutilated_pose}]}).is_empty(), "Collapsed mutilated scales remain valid")
	_check(VALIDATOR.error({"version": 8, "objects": [{"scene": "res://corpse.tscn", "settled_physics": {"version": 1}, "decor_pose": saved_pose}]}).is_empty(), "Pose survives JSON validation")
	var clone := HUNGER.instantiate() as Node3D
	clone.call("configure_decor_pose", saved_pose)
	clone.transform = corpse.transform
	stage.add_child(clone)
	var before: Skeleton3D = corpse.get("parts").get("skeleton")
	var after: Skeleton3D = clone.get("parts").get("skeleton")
	for index in before.get_bone_count():
		_check(before.get_bone_pose(index).is_equal_approx(after.get_bone_pose(index)), "Bone pose restores exactly: " + before.get_bone_name(index))
	PHYSICS.resume([box, clone, part])
	_check(box.sleeping and part.sleeping, "Prepared props resume asleep")
	_check(clone.get("_physics") == null and corpse.get("_physics") == null, "Prepared corpse releases simulator and loads without one")
	await _round_trip(stage, corpse, part)
	await _repeat_pose(stage, corpse, label)
	_freed_warnings(stage)
	_warning_budget(stage)
	_anchor_replacement(stage)
	await _low_fps(stage, label)
	await _timeout_snapshot(stage, label)
	await _whole_location(label)
	_freed_resume(stage)
	var position_before := box.position
	paused = false
	for frame in 30:
		await physics_frame
	_check(box.position.distance_to(position_before) < 0.005, "Prepared body does not reposition after loading")
	box.position.y += 1
	PHYSICS.resume([box])
	_check(not box.sleeping, "Transform edits invalidate sleep")
	var bad := saved_pose.duplicate(true)
	bad.physics_v1.body = [1, 2]
	_check(not VALIDATOR.error({"objects": [{"scene": "res://corpse.tscn", "decor_pose": bad}]}).is_empty(), "Malformed pose rejected before loading")
	stage.queue_free()
	await process_frame
	print("Planning settle tests: %d failures" % failures)
	quit(failures)

func _round_trip(stage: Node3D, corpse: Node3D, part: RigidBody3D) -> void:
	var objects := preload("res://game/bootstrap/app/planning_objects.gd").new()
	stage.add_child(objects)
	var controls := Controls.new()
	controls.add_child(controls.status)
	stage.add_child(controls)
	var history := preload("res://game/bootstrap/app/planning_edit_history.gd").new()
	var session := {"root": stage, "enemies_root": stage, "main_player": Node3D.new(), "edit_history": history, "active": true}
	stage.add_child(session.main_player)
	objects.configure({"session": session, "catalog": preload("res://game/bootstrap/app/planning_catalog.gd").new(), "controls": controls, "geometry": Geometry.new()})
	corpse.set_meta("planning_scene_path", HUNGER.resource_path)
	part.set_meta("planning_scene_path", PART.resource_path)
	var data := preload("res://game/bootstrap/app/planning_layout_capture.gd").collect(objects, [corpse, part])
	for record: Dictionary in data.objects:
		_check(record.get("settled_physics", {}).get("version") == 1, "Prepared state is persisted")
	var file := preload("res://game/bootstrap/app/planning_map_file.gd")
	var path := "user://issue237_physics_round_trip.json"
	_check(not file.write(path, data).has("error"), "Prepared map writes atomically")
	var read: Dictionary = file.read(path)
	_check(not read.has("error"), "Prepared map file validates")
	_check(objects._apply_layout_data(read.data).get("loaded") == 2, "Actual map loader restores both records")
	PHYSICS.resume(objects.placed)
	for node: Node3D in objects.placed:
		if node is RigidBody3D:
			_check(node.sleeping and node.transform.is_equal_approx(part.transform), "Loaded part retains transform/sleep")
		else:
			_check(node.get("_physics") == null and node.transform.is_equal_approx(corpse.transform), "Loaded corpse keeps pose without physics")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	await _baked_pose(stage, objects.catalog, corpse, part, controls.status)
	var chair_y := -0.00001
	var chair_report: Dictionary = objects._apply_layout_data({"version": 8, "objects": [{"scene": "res://models/objects/enviroments/06/06_conference_chair.glb", "x": 10, "y": chair_y, "settled_physics": {"version": 1}}]})
	_check(chair_report.get("loaded") == 1, "Prepared conference chair loads")
	_check(absf(objects.placed[0].position.y - chair_y) < 0.000001, "Ready preserves prepared chair height instead of adding 2.5 cm")
	await process_frame


func _baked_pose(stage: Node3D, catalog: RefCounted, corpse: Node3D, part: Node3D, status: Label) -> void:
	var path := "user://issue237_pose_bake.tscn"
	var bake := preload("res://game/bootstrap/app/planning_scene_bake.gd").new(catalog)
	_check(await bake.save_async([corpse, part], path, stage, status) == OK, "Prepared scene bakes in frame slices")
	var scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var baked := scene.instantiate() as Node3D
	stage.add_child(baked)
	var loaded := baked.get_child(0) as Node3D
	PHYSICS.resume([loaded])
	_check(loaded.get("_physics") == null, "Baked corpse loads without simulator")
	var source: Skeleton3D = corpse.get("parts").get("skeleton")
	var target: Skeleton3D = loaded.get("parts").get("skeleton")
	for index in source.get_bone_count():
		_check(source.get_bone_pose(index).is_equal_approx(target.get_bone_pose(index)), "Baked bone pose restores: " + source.get_bone_name(index))
	baked.free()
	DirAccess.remove_absolute(path)


func _repeat_pose(stage: Node3D, corpse: Node3D, status: Label) -> void:
	var snapshot: Dictionary = corpse.call("get_decor_pose")
	await SETTLE.new().run(stage, [corpse], status)
	var unchanged := SETTLE.new()
	await unchanged.run(stage, [corpse], status)
	_check(unchanged.ticks == 0, "Unchanged prepared layer skips physics")
	_check(corpse.get("_physics") == null, "Preparation releases physical bones")
	corpse.position.y += 0.3
	var moved := SETTLE.new()
	_check(await moved.run(stage, [corpse], status), "Edited corpse prepares again with a fresh simulator")
	_check(corpse.get("_physics") == null, "Repeated preparation releases simulator")
	_check(corpse.call("get_decor_pose") != snapshot, "Edited corpse retains its new physical pose")


func _warning_budget(stage: Node3D) -> void:
	var objects := WarningObjects.new()
	stage.add_child(objects)
	for index in 200:
		var body := RigidBody3D.new()
		body.position = Vector3(index * 2, 4, 10)
		objects.add_child(body)
		objects.placed.append(body)
	var warning := STABILITY.new()
	for frame in 40:
		warning.update(objects, Geometry.new())
	_check(warning.get("_marks").size() <= STABILITY.MAX_MARKERS, "Warnings have a bounded render budget")
	objects.selected = objects.placed[-1]
	warning.update(objects, Geometry.new())
	_check(warning.get("_marks").has(objects.selected), "Selection has priority when warning budget is full")
	var camera := Camera3D.new()
	stage.add_child(camera)
	warning.update(objects, Geometry.new(), camera)
	_check(warning.get("_marks").size() == 1, "Off-camera warning meshes are released")
	warning.clear()
	_check(warning.get("_marks").is_empty(), "Exiting clears warning visuals")
	objects.free()
	camera.free()


func _anchor_replacement(stage: Node3D) -> void:
	var old := RigidBody3D.new()
	old.freeze = true
	old.set_meta("planning_auto_fixture", "extinguisher")
	old.set_meta("planning_scene_path", "res://fixture.tscn")
	old.set_meta("planning_settled_transform", old.transform)
	old.set_meta("planning_settled_count", 7)
	stage.add_child(old)
	var stamps := PHYSICS.capture_anchors([old])
	old.free()
	var replacement := RigidBody3D.new()
	replacement.freeze = true
	replacement.set_meta("planning_auto_fixture", "extinguisher")
	replacement.set_meta("planning_scene_path", "res://fixture.tscn")
	stage.add_child(replacement)
	PHYSICS.restore_anchors([replacement], stamps)
	_check(replacement.has_meta("planning_settled_transform"), "Identical regenerated fixture retains preparation")
	_check(replacement.get_meta("planning_settled_count", -1) == 7, "Fixture retains prepared layer count")
	replacement.position.x += 1
	_check(PHYSICS.capture_anchors([replacement]).is_empty(), "Moved fixture invalidates preparation")
	replacement.free()


func _low_fps(stage: Node3D, status: Label) -> void:
	var body := RigidBody3D.new()
	body.position = Vector3(-10, 1.5, 0)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	stage.add_child(body)
	var previous_limit := Engine.max_fps
	Engine.max_fps = 12
	var first := Engine.get_physics_frames()
	var job := SETTLE.new()
	var result := await job.run(stage, [body], status)
	var advanced := Engine.get_physics_frames() - first
	Engine.max_fps = previous_limit
	_check(result, "Low-FPS preparation completes")
	_check(job.ticks >= advanced - 12, "Budgets count physical ticks, including multiple ticks per rendered frame")
	body.free()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _freed_warnings(stage: Node3D) -> void:
	var warning := STABILITY.new()
	var objects := WarningObjects.new()
	stage.add_child(objects)
	var body := RigidBody3D.new()
	stage.add_child(body)
	body.position.y = 5
	objects.placed.append(body)
	warning.update(objects, Geometry.new())
	_check(warning.get("_marks").size() == 1, "Unsettled body creates warning")
	# Warning lifetime may end before the next owner update.
	body.get_node("PlanningStabilityWarning").free()
	warning.update(objects, Geometry.new())
	_check(warning.get("_marks").size() == 1, "Freed warning is replaced")
	body.free()
	warning.update(objects, Geometry.new())
	objects.placed.clear()
	_check(warning.get("_marks").is_empty(), "Deleted body is pruned without assigning freed marker")
	warning.clear()
	objects.free()


func _freed_resume(stage: Node3D) -> void:
	var live := RigidBody3D.new()
	stage.add_child(live)
	var gone := Node3D.new()
	var entries: Array = [gone, live]
	gone.free()
	PHYSICS.resume(entries)
	_check(is_instance_valid(live), "Resume tolerates a freed entry before a live body")
	_check(PHYSICS.capture_anchors(entries).is_empty(), "Anchor capture tolerates freed entries")
	PHYSICS.restore_anchors(entries, [])
	live.free()


func _timeout_snapshot(stage: Node3D, status: Label) -> void:
	var body := RigidBody3D.new()
	body.position = Vector3(2, 20, 2)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	stage.add_child(body)
	body.set_meta("planning_settled_transform", Transform3D())
	body.set_meta("planning_settled_count", 1)
	var job := SETTLE.new()
	job.tick_limit = 1
	_check(not await job.run(stage, [body], status), "Unfinished physics is reported honestly")
	_check(not job.failure_reason.is_empty(), "Timeout explains why no prepared snapshot is available")
	_check(not body.has_meta("planning_settled_transform"), "Unsettled authored placement is not stamped as prepared")
	body.free()


func _cube(parent: Node3D, at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	parent.add_child(body)
	body.owner = parent
	shape.owner = parent
	return body


func _whole_location(status: Label) -> void:
	var stage := Node3D.new()
	stage.position.x = 100
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.1
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(40, 0.2, 40)
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.owner = stage
	shape.owner = stage
	# The upper prop was in the first 192-body batch, its support in a later
	# batch. Both begin in the air and must fall together to real ground.
	var upper := _cube(stage, Vector3(0, 5, 0))
	var nodes: Array = [upper]
	for index in 200:
		var x := float(index % 15) * 2.0 - 14.0
		var z := float(floori(float(index) / 15)) * 2.0 - 14.0
		if absf(x) < 0.1 and absf(z) < 0.1: continue
		nodes.append(_cube(stage, Vector3(x, 1.5, z)))
	var lower := _cube(stage, Vector3(0, 3, 0))
	nodes.append(lower)
	var bin: Node3D = preload("res://game/bootstrap/app/planning_catalog.gd").new()._instantiate_asset("res://models/objects/enviroments/09/09_trash_bin_small.glb")
	bin.position = Vector3(3, 0.015, 17)
	stage.add_child(bin)
	bin.owner = stage
	nodes.append(bin)
	var job := SETTLE.new()
	_check(await job.run(stage, nodes, status), "Entire scene settles together across the former batch boundary")
	_check(absf(lower.position.y - 0.5) < 0.04 and absf(upper.position.y - 1.5) < 0.04, "Falling support and upper prop reach their actual final positions")
	for node: RigidBody3D in nodes:
		_check(node.sleeping and node.get_meta("planning_settled_transform") == node.transform, "Only final transforms receive prepared sleep stamps")
	var packed := PackedScene.new()
	_check(packed.pack(stage) == OK, "Settled location packs as a scene")
	var loaded := packed.instantiate() as Node3D
	loaded.position.x = 200
	root.add_child(loaded)
	PHYSICS.resume(loaded.get_children())
	var loader := preload("res://game/bootstrap/app/menu/mission_loader.gd").new()
	loader.pending = loaded
	var frame_before := Engine.get_process_frames()
	await loader._settle_props(self)
	_check(Engine.get_process_frames() == frame_before, "Prepared map skips the loading-time physics settle loop")
	loader.free()
	var transforms := {}
	for node in loaded.get_children():
		if node is RigidBody3D:
			_check(node.sleeping, "Loading does not wake prepared furniture")
			transforms[node] = node.transform
	paused = false
	for frame in 60: await physics_frame
	for node: RigidBody3D in transforms:
		var before: Transform3D = transforms[node]
		var rotation_delta := before.basis.get_rotation_quaternion().angle_to(node.basis.get_rotation_quaternion())
		_check(node.position.distance_to(before.origin) < 0.001 and rotation_delta < 0.001 and node.sleeping, "Loaded furniture stays at its final pose (1 mm / 0.001 rad contact tolerance)")
	paused = true
	loaded.free()
	stage.free()
