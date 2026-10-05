extends SceneTree
const POSES := preload("res://game/features/infected/decor_pose.gd")
const HUNGER := preload("res://game/features/infected/public/decor/corpse_hunger.tscn")
const HORDE := preload("res://game/features/infected/public/decor/corpse_horde.tscn")
var failures := 0
var stage: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	stage.add_child(floor_body)
	floor_body.position.y = -.1
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(60, .2, 60)
	floor_body.add_child(shape)
	await _settle(HUNGER, Vector3.ONE, "seated")
	await _settle(HORDE, Vector3.ONE, "back")
	await _settle(HUNGER, Vector3.ONE * 1.2, "right_side")
	stage.queue_free()
	await process_frame
	print("Corpse physics tests: %d failures" % failures)
	quit(failures)

func _settle(scene: PackedScene, size: Vector3, pose: String) -> void:
	var corpse := scene.instantiate() as Node3D
	corpse.call("configure_decor_pose", {"seed": 9, "pose": pose, "facing": 0.0})
	stage.add_child(corpse)
	corpse.position = Vector3(0, 3, 0)
	corpse.scale = size
	var parts: Node = corpse.get("parts")
	var skeleton: Skeleton3D = parts.get("skeleton")
	var authored_scale := (skeleton.global_basis * skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).basis).get_scale()
	corpse.call("set_runtime_physics", true)
	var simulation: PhysicalBoneSimulator3D = corpse.get("_physics").get("simulator")
	var links: Array[Dictionary] = []
	for child: PhysicalBone3D in simulation.get_children():
		var parent_id := skeleton.get_bone_parent(child.get_bone_id())
		var parent := simulation.get_node_or_null("Physics_" + skeleton.get_bone_name(parent_id)) as PhysicalBone3D if parent_id >= 0 else null
		if parent != null:
			links.append({"child": child, "parent": parent, "length": _joint(child).distance_to(_joint(parent))})
	for frame in 120:
		await physics_frame
	for link in links:
		_check(absf(_joint(link["child"]).distance_to(_joint(link["parent"])) - float(link["length"])) < .065, "Joints retain anatomical segment lengths: " + corpse.name)
	var sample := {"scale": Vector3.ZERO, "bounds": AABB()}
	var capture_pose := func() -> void:
		sample["scale"] = (skeleton.global_basis * skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).basis).get_scale()
		sample["bounds"] = corpse.global_transform * POSES.bounds(parts, corpse)
	skeleton.skeleton_updated.connect(capture_pose)
	await process_frame
	await process_frame
	skeleton.skeleton_updated.disconnect(capture_pose)
	_check(Vector3(sample["scale"]).is_equal_approx(authored_scale), "Physics preserves authored model scale: " + corpse.name)
	_check(AABB(sample["bounds"]).position.y >= -.04, "Visible corpse skin remains above floor: " + corpse.name)
	_check(AABB(sample["bounds"]).position.y < .3, "Corpse rests against floor: " + corpse.name)
	parts.call("sever", &"arm_l" if scene == HUNGER else &"tentacle_0", Vector3.ZERO, false)
	await process_frame
	_check(not simulation.has_node("Physics_L_UpperArm" if scene == HUNGER else "Physics_T0_A"), "Severing removes physical bones")
	corpse.queue_free()
	await process_frame

func _joint(bone: PhysicalBone3D) -> Vector3:
	return bone.global_transform * bone.body_offset.affine_inverse().origin

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
