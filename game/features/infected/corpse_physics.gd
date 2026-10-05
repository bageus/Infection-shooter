extends RefCounted
## Build bounded articulated collision volumes from the existing body-part rig.
var simulator: PhysicalBoneSimulator3D
var skeleton: Skeleton3D
var _bones: Dictionary = {}


func setup(parts: Node) -> void:
	skeleton = parts.get("skeleton") as Skeleton3D
	if skeleton == null:
		return
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "CorpsePhysics"
	simulator.active = false
	skeleton.add_child(simulator)
	var definitions: Dictionary = parts.get("parts")
	var segments: Array[Dictionary] = []
	for label: StringName in definitions:
		var definition: Dictionary = definitions[label]
		if definition["severed"]:
			continue
		_bones[label] = []
		for segment: Dictionary in definition["segments"]:
			var entry := segment.duplicate()
			entry["part"] = label
			segments.append(entry)
	# Parents must exist and have their posed transform before child joints bind.
	segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["bone"]) < int(b["bone"]))
	for segment in segments:
		var bone := _build(segment)
		_bones[segment["part"]].append(bone)
	for bone: PhysicalBone3D in simulator.get_children():
		bone.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(bone.get_bone_id()) * bone.body_offset
	for bone: PhysicalBone3D in simulator.get_children():
		bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		bone.set("joint_constraints/swing_span", 45.0)
		bone.set("joint_constraints/twist_span", 25.0)
	# All volumes are linked at skeleton joints; own limbs never collide.
	var volumes := simulator.get_children()
	for a: PhysicalBone3D in volumes:
		for b: PhysicalBone3D in volumes:
			if a != b:
				a.add_collision_exception_with(b)
	parts.connect("part_severed", _severed)


func _build(segment: Dictionary) -> PhysicalBone3D:
	var index := int(segment["bone"])
	var bone := PhysicalBone3D.new()
	bone.name = "Physics_" + skeleton.get_bone_name(index)
	bone.set("bone_name", skeleton.get_bone_name(index))
	bone.collision_layer = 0 # Bullet hits keep using damage-aware bone hitboxes.
	bone.collision_mask = 1
	bone.mass = 3.0
	bone.linear_damp = .7
	bone.angular_damp = 2.5
	bone.friction = .9
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	var rest := skeleton.get_bone_global_rest(index)
	var start: Vector3 = rest.affine_inverse() * Vector3(segment["start"])
	var end: Vector3 = rest.affine_inverse() * Vector3(segment["end"])
	var axis := end - start
	var radius := clampf(float(segment["radius"]) * 1.5, .03, 1.0)
	var capsule := CapsuleShape3D.new()
	var world_bone := skeleton.global_transform * skeleton.get_bone_global_pose(index)
	var world_radius := radius * world_bone.basis.get_scale().abs()[world_bone.basis.get_scale().abs().max_axis_index()]
	capsule.radius = world_radius
	capsule.height = (world_bone.basis * axis).length() + world_radius * 2.0
	var alignment := Basis(Quaternion(Vector3.UP, axis.normalized())) if axis.length_squared() > .00001 else Basis.IDENTITY
	# Physics bodies have unit scale. Offset inverse restores the authored skin scale.
	var physical_basis := (world_bone.basis * alignment).orthonormalized()
	var offset_basis := world_bone.basis.inverse() * physical_basis
	bone.body_offset = Transform3D(offset_basis, (start + end) * .5)
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	bone.add_child(shape)
	simulator.add_child(bone)
	return bone


func set_enabled(enabled: bool) -> void:
	if not is_instance_valid(simulator):
		return
	if enabled:
		simulator.active = true
		simulator.physical_bones_start_simulation()
	else:
		simulator.physical_bones_stop_simulation()
		simulator.active = false


func _severed(part: StringName, _piece: RigidBody3D) -> void:
	for bone: PhysicalBone3D in _bones.get(part, []):
		if is_instance_valid(bone):
			bone.queue_free()
	_bones.erase(part)
