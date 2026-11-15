extends RefCounted
## Rotate the entire authored gun; its public muzzle and flash stay on the barrel.

static func aim(weapon: Node3D, muzzle: Node3D, target: Vector3) -> void:
	# The turn pivots on the muzzle: it stays where the drawn gun's barrel ends and the shot leaves straight for the target.
	var pivot := muzzle.global_position
	var axis := -muzzle.global_basis.z.normalized()
	var wanted := target - pivot
	if wanted.length_squared() < 0.000001:
		return
	var turn := Basis(Quaternion(axis, wanted.normalized()))
	weapon.global_basis = turn * weapon.global_basis
	weapon.global_position = pivot + turn * (weapon.global_position - pivot)


static func collision_origin(weapon: Node3D, muzzle: Node3D) -> Vector3:
	var axis := -muzzle.global_basis.z.normalized()
	var barrel_reach := maxf(0.0, (muzzle.global_position - weapon.global_position).dot(axis))
	return muzzle.global_position - axis * barrel_reach
