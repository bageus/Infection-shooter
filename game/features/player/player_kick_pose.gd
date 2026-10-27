extends SkeletonModifier3D
## Torso jolt on a shot: pitches the spine up a little; hands and weapon follow.
const MAX_DEGREES := 2.5
var mount: Node
var _spine := -1


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	var recoil: Object = mount.get("recoil") if mount != null else null
	if skeleton == null or recoil == null or float(recoil.get("kick")) <= 0.0:
		return
	var weapon := mount.get("_active") as Node3D
	var muzzle := weapon.get_node_or_null("Muzzle") as Node3D if is_instance_valid(weapon) else null
	if _spine < 0:
		for label in ["Spine", "mixamorig:Spine", "Chest"]:
			_spine = skeleton.find_bone(label)
			if _spine >= 0:
				break
	if _spine < 0 or muzzle == null:
		return
	var forward := -muzzle.global_basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		return
	var right := forward.normalized().cross(Vector3.UP)
	var pose := skeleton.get_bone_global_pose(_spine)
	var world_basis := Basis(right, deg_to_rad(MAX_DEGREES) * float(recoil.get("kick"))) * (skeleton.global_basis * pose.basis)
	var parent := skeleton.get_bone_parent(_spine)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := parent_basis.inverse() * skeleton.global_basis.inverse() * world_basis
	skeleton.set_bone_pose_rotation(_spine, local.orthonormalized().get_rotation_quaternion())
