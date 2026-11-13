extends SkeletonModifier3D
## The walk clips lean the whole body back; tip the torso by the pitch the run clips give the hips
## (Run_Forward +5.4 deg, Run_Backward -10.4 deg): a little forward walking, more sprinting, back when backpedalling.
const WALK_LEAN := deg_to_rad(6.0)
const RUN_LEAN := deg_to_rad(12.0)
const BACK_LEAN := deg_to_rad(-5.0)
const SIDE_LEAN := deg_to_rad(4.0)
const WALK_SPEED := 5.4
const RUN_SPEED := 8.1
const EASE_RATE := 8.0
var player: CharacterBody3D
var lean := 0.0
var _spine := -1


## Lean for a velocity in the skeleton's frame (+Z is front).
static func target_lean(velocity: Vector3) -> float:
	var forward := velocity.z
	var along := 0.0
	if forward >= 0.0:
		along = WALK_LEAN * minf(forward / WALK_SPEED, 1.0) + (RUN_LEAN - WALK_LEAN) * clampf((forward - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	else:
		along = BACK_LEAN * minf(-forward / WALK_SPEED, 1.0)
	return along + SIDE_LEAN * minf(absf(velocity.x) / WALK_SPEED, 1.0)


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or player == null:
		return
	if _spine < 0:
		_spine = skeleton.find_bone("Spine")
		if _spine < 0:
			return
	var local := skeleton.global_basis.inverse() * Vector3(player.velocity.x, 0.0, player.velocity.z)
	lean = lerpf(lean, target_lean(local), 1.0 - exp(-EASE_RATE * delta))
	# Skeleton space: +Z is front, so a positive turn about X tips the torso forward.
	var tipped := Basis(Vector3.RIGHT, lean) * skeleton.get_bone_global_pose(_spine).basis
	var parent := skeleton.get_bone_parent(_spine)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(_spine, (parent_basis.inverse() * tipped).orthonormalized().get_rotation_quaternion())
