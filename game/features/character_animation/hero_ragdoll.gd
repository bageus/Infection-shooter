extends RefCounted
## The dead hero lets go once his fall-backward clip has ended (Vadim): capsule volumes on the main bones turn the
## lying body into a ragdoll that settles loosely on the floor. Presentation only; the player's own capsule is ignored.

## Bone, the bone its capsule runs to ("" = a short stub), capsule radius in metres, joint swing and twist in degrees.
const BONES := [
	["Hips", "Spine", 0.13, 20.0, 10.0], ["Spine", "Spine1", 0.12, 15.0, 10.0], ["Spine1", "Spine2", 0.12, 15.0, 10.0],
	["Spine2", "Neck", 0.12, 15.0, 10.0], ["Neck", "Head", 0.05, 35.0, 15.0], ["Head", "", 0.1, 35.0, 15.0],
	["LeftArm", "LeftForeArm", 0.05, 70.0, 20.0], ["LeftForeArm", "LeftHand", 0.045, 75.0, 6.0],
	["RightArm", "RightForeArm", 0.05, 70.0, 20.0], ["RightForeArm", "RightHand", 0.045, 75.0, 6.0],
	["LeftUpLeg", "LeftLeg", 0.08, 30.0, 8.0], ["LeftLeg", "LeftFoot", 0.065, 40.0, 4.0], ["LeftFoot", "LeftToeBase", 0.04, 30.0, 5.0],
	["RightUpLeg", "RightLeg", 0.08, 30.0, 8.0], ["RightLeg", "RightFoot", 0.065, 40.0, 4.0], ["RightFoot", "RightToeBase", 0.04, 30.0, 5.0],
]
## Length (metres) of the capsule of a bone without a child bone.
const STUB := 0.18
## Physics layer of floors, walls and props.
const WORLD_MASK := 1


## Starts the ragdoll on `skeleton`; `owner_body` (the player's capsule) is never collided with. Returns the simulator, or null without the bones.
static func start(skeleton: Skeleton3D, owner_body: CollisionObject3D) -> PhysicalBoneSimulator3D:
	if skeleton == null or not skeleton.is_inside_tree() or skeleton.find_bone("Hips") < 0:
		return null
	var simulator := PhysicalBoneSimulator3D.new()
	simulator.name = "HeroRagdoll"
	simulator.active = false
	skeleton.add_child(simulator)
	for entry: Array in BONES:
		var bone := _build(skeleton, simulator, entry, owner_body)
		if bone != null:
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			bone.set("joint_constraints/swing_span", float(entry[3]))
			bone.set("joint_constraints/twist_span", float(entry[4]))
	var volumes := simulator.get_children()
	for i in volumes.size():
		for j in range(i + 1, volumes.size()):
			(volumes[i] as PhysicalBone3D).add_collision_exception_with(volumes[j])
	simulator.active = true
	simulator.physical_bones_start_simulation()
	return simulator


static func _build(skeleton: Skeleton3D, simulator: PhysicalBoneSimulator3D, entry: Array, owner_body: CollisionObject3D) -> PhysicalBone3D:
	var index := skeleton.find_bone(String(entry[0]))
	if index < 0:
		return null
	var world_bone := skeleton.global_transform * skeleton.get_bone_global_pose(index)
	var child := skeleton.find_bone(String(entry[1])) if not String(entry[1]).is_empty() else -1
	var end_world := world_bone.origin
	if child >= 0:
		end_world = (skeleton.global_transform * skeleton.get_bone_global_pose(child)).origin
	else:
		var parent := skeleton.get_bone_parent(index)
		var away := world_bone.origin - (skeleton.global_transform * skeleton.get_bone_global_pose(parent)).origin if parent >= 0 else Vector3.UP
		end_world += away.normalized() * STUB
	var radius := float(entry[2])
	var axis_world := end_world - world_bone.origin
	var bone := PhysicalBone3D.new()
	bone.name = "Physics_" + String(entry[0])
	bone.set("bone_name", String(entry[0]))
	bone.collision_layer = 0
	bone.collision_mask = WORLD_MASK
	bone.mass = 3.0
	bone.linear_damp = 0.7
	bone.angular_damp = 2.5
	bone.friction = 0.9
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = axis_world.length() + radius * 2.0
	var alignment := Basis(Quaternion(Vector3.UP, axis_world.normalized())) if axis_world.length_squared() > 0.00001 else Basis.IDENTITY
	# Physics bodies have unit scale; the offset restores the skin's own scale and puts the capsule on the bone.
	var offset_basis := world_bone.basis.inverse() * (world_bone.basis.orthonormalized() * alignment)
	bone.body_offset = Transform3D(offset_basis, world_bone.affine_inverse() * (world_bone.origin + axis_world * 0.5))
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	bone.add_child(shape)
	simulator.add_child(bone)
	if owner_body != null:
		bone.add_collision_exception_with(owner_body)
	return bone
