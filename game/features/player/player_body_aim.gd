extends SkeletonModifier3D
## Aim through the torso; both hands and their socket inherit the same turn.
var mount: Node
const BODY_TURN_RATE := 14.0
const TORSO_PITCH_SHARE := 0.15
var _spine := -1
var _shoulders: Array[int] = []


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or mount == null:
		return
	if _spine < 0:
		for label in ["Spine", "mixamorig:Spine", "Chest"]:
			_spine = skeleton.find_bone(label)
			if _spine >= 0:
				break
	if _shoulders.is_empty():
		for label in ["LeftShoulder", "RightShoulder"]:
			if skeleton.find_bone(label) >= 0:
				_shoulders.append(skeleton.find_bone(label))
	if _spine < 0:
		return
	var target: Vector3 = mount.get("_aim_target")
	var weapon := mount.get("_active") as Node3D
	if not target.is_finite() or not is_instance_valid(weapon):
		return
	mount.set("_aim_modifying", true)
	for iteration in 2:
		mount.call("sync_weapon", weapon)
		var muzzle := weapon.get_node_or_null("Muzzle") as Node3D
		if muzzle == null:
			break
		var pose := skeleton.get_bone_global_pose(_spine)
		var pivot := skeleton.global_transform * pose.origin
		var axis := -muzzle.global_basis.z.normalized()
		var offset := muzzle.global_position - pivot
		var transverse := offset - axis * offset.dot(axis)
		var destination := target - pivot
		if destination.length_squared() <= transverse.length_squared() + .0001:
			break
		var reference := transverse + axis * sqrt(destination.length_squared() - transverse.length_squared())
		var turn := Basis(Quaternion(reference.normalized(), destination.normalized()))
		# Yaw turns the torso; pitch is mostly raised/lowered by the arms, the torso only leans slightly.
		var full := turn.get_rotation_quaternion()
		var yaw := Quaternion(0.0, full.y, 0.0, full.w).normalized()
		var pitch := full * yaw.inverse()
		_rotate(skeleton, _spine, yaw * Quaternion.IDENTITY.slerp(pitch, TORSO_PITCH_SHARE))
		var arms := Quaternion.IDENTITY.slerp(pitch, 1.0 - TORSO_PITCH_SHARE)
		for shoulder in _shoulders:
			_rotate(skeleton, shoulder, arms)
	mount.call("sync_weapon", weapon)
	mount.set("_aim_modifying", false)


## Rotates a bone by a world-space rotation.
func _rotate(skeleton: Skeleton3D, bone: int, world_turn: Quaternion) -> void:
	var world_basis := Basis(world_turn) * (skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis)
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := parent_basis.inverse() * skeleton.global_basis.inverse() * world_basis
	skeleton.set_bone_pose_rotation(bone, local.orthonormalized().get_rotation_quaternion())


## Eases the body yaw toward the aim so a cursor flip does not snap 180 degrees; aim_pivot (bullets) stays exact.
static func turn_body(body: Node3D, direction: Vector3, delta: float) -> void:
	var yaw := lerp_angle(body.global_rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-BODY_TURN_RATE * delta))
	body.global_rotation = Vector3(0.0, yaw, 0.0)
