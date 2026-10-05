extends RefCounted
## Rotate the entire authored gun; its public muzzle and flash stay on the barrel.

static func aim(weapon: Node3D, muzzle: Node3D, target: Vector3) -> void:
	var offset := muzzle.global_position - weapon.global_position
	var axis := -muzzle.global_basis.z.normalized()
	var target_offset := target - weapon.global_position
	if target_offset.length_squared() < 0.000001:
		return
	var along := offset.dot(axis)
	var transverse := offset - axis * along
	var reach := sqrt(maxf(0.0, target_offset.length_squared() - transverse.length_squared()))
	var reference := transverse + axis * reach
	if reference.length_squared() < 0.000001:
		reference = axis
	var turn := Basis(Quaternion(reference.normalized(), target_offset.normalized()))
	weapon.global_basis = turn * weapon.global_basis


static func collision_origin(weapon: Node3D, muzzle: Node3D) -> Vector3:
	var axis := -muzzle.global_basis.z.normalized()
	var barrel_reach := maxf(0.0, (muzzle.global_position - weapon.global_position).dot(axis))
	return muzzle.global_position - axis * barrel_reach
