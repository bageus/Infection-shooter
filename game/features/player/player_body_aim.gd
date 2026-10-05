extends SkeletonModifier3D
## Aim through the torso; both hands and their socket inherit the same turn.
var mount: Node
var _spine := -1


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or mount == null:
		return
	if _spine < 0:
		for label in ["Spine", "mixamorig:Spine", "Chest"]:
			_spine = skeleton.find_bone(label)
			if _spine >= 0:
				break
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
		var world_basis := turn * (skeleton.global_basis * pose.basis)
		var parent := skeleton.get_bone_parent(_spine)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var local := parent_basis.inverse() * skeleton.global_basis.inverse() * world_basis
		skeleton.set_bone_pose_rotation(_spine, local.orthonormalized().get_rotation_quaternion())
	mount.call("sync_weapon", weapon)
	mount.set("_aim_modifying", false)
