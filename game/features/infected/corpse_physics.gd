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
	for label: StringName in parts.get("parts"):
		var definition: Dictionary = parts.get("parts")[label]
		if definition["severed"]:
			continue
		var created: Array[PhysicalBone3D] = []
		for segment: Dictionary in definition["segments"]:
			var bone := _build(segment)
			created.append(bone)
		_bones[label] = created
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
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
	var rest := skeleton.get_bone_global_rest(index)
	var start: Vector3 = rest.affine_inverse() * Vector3(segment["start"])
	var end: Vector3 = rest.affine_inverse() * Vector3(segment["end"])
	var axis := end - start
	var radius := clampf(float(segment["radius"]) * .65, .025, .2)
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(axis.length(), radius * 2.0)
	var basis := Basis(Quaternion(Vector3.UP, axis.normalized())) if axis.length_squared() > .00001 else Basis.IDENTITY
	bone.body_offset = Transform3D(basis, (start + end) * .5)
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
