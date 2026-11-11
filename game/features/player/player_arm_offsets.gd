extends SkeletonModifier3D
## Runs after every other pose modifier and turns arm bones by extra angles taken from
## the equipment pose's ARM_TUNING for the held weapon. The weapon hold tuner switches
## the pose to manual mode and drives `offsets` itself.
var pose: SkeletonModifier3D
## bone name ("RightArm", "RightForeArm", "RightHand", ...) -> Vector3 of degrees; used in manual mode only.
var offsets := {}


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or pose == null:
		return
	var turns: Dictionary = offsets if pose.manual_arms else pose.arm_bones()
	for bone_name in turns:
		var bone := skeleton.find_bone(bone_name)
		var turn: Vector3 = turns[bone_name]
		if bone < 0 or turn.is_zero_approx():
			continue
		var extra := Quaternion.from_euler(Vector3(deg_to_rad(turn.x), deg_to_rad(turn.y), deg_to_rad(turn.z)))
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * extra)
