extends SkeletonModifier3D
## The walk clips lean the whole body back; tip the torso forward while the hero moves.
const LEAN := deg_to_rad(8.0)
const EASE_RATE := 8.0
const MOVING_SPEED := 0.15
var player: CharacterBody3D
var lean := 0.0
var _spine := -1


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or player == null:
		return
	if _spine < 0:
		_spine = skeleton.find_bone("Spine")
		if _spine < 0:
			return
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > MOVING_SPEED
	lean = lerpf(lean, LEAN if moving else 0.0, 1.0 - exp(-EASE_RATE * delta))
	# Skeleton space: +Z is front, so a positive turn about X tips the torso forward.
	var tipped := Basis(Vector3.RIGHT, lean) * skeleton.get_bone_global_pose(_spine).basis
	var parent := skeleton.get_bone_parent(_spine)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(_spine, (parent_basis.inverse() * tipped).orthonormalized().get_rotation_quaternion())
