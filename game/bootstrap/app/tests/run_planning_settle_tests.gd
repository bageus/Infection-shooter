extends SceneTree
const SETTLE := preload("res://game/bootstrap/app/planning_settle.gd")
const STABILITY := preload("res://game/bootstrap/app/planning_stability.gd")
const PHYSICS := preload("res://game/bootstrap/app/planning_physics.gd")
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
const HUNGER := preload("res://game/features/infected/public/decor/corpse_hunger.tscn")
const PART := preload("res://game/features/infected/public/decor/part_horde_tentacle.tscn")
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
	mutilated.position = Vector3(5, 1, 5)
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
	await process_frame

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
