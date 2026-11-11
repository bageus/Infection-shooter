extends SkeletonModifier3D
## Runs after every other pose modifier and turns chosen arm bones by extra angles,
## so the hold tuner can rotate shoulders, elbows and wrists by hand.
## offsets: bone name ("RightArm", "RightForeArm", "RightHand", ...) -> Vector3 of degrees.
var offsets := {}


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone_name in offsets:
		var bone := skeleton.find_bone(bone_name)
		var turn: Vector3 = offsets[bone_name]
		if bone < 0 or turn.is_zero_approx():
			continue
		var extra := Quaternion.from_euler(Vector3(deg_to_rad(turn.x), deg_to_rad(turn.y), deg_to_rad(turn.z)))
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * extra)
