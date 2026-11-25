extends SkeletonModifier3D
## The baked forward and backward run cycles plant the right foot about 25 degrees more toe-out than the left, which
## reads as the right boot standing sideways (Vadim). While one of them plays, the right foot is turned back about the
## vertical by FIX_DEGREES; the weight eases in and out so a change of clip does not snap the boot.

const FIX_DEGREES := 25.0
const EASE_PER_SECOND := 12.0

var player: AnimationPlayer
var _weight := 0.0


func _process_modification() -> void:
	var clip := String(player.current_animation) if player != null else ""
	var wanted := 1.0 if clip.begins_with("Run_Forward") or clip.begins_with("Run_Backward") else 0.0
	_weight = move_toward(_weight, wanted, EASE_PER_SECOND * get_process_delta_time())
	if _weight <= 0.0:
		return
	var skeleton := get_skeleton()
	var foot := skeleton.find_bone("RightFoot")
	if foot < 0:
		return
	var parent := skeleton.get_bone_parent(foot)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis
	var turned := Basis(Vector3.UP, deg_to_rad(FIX_DEGREES) * _weight) * skeleton.get_bone_global_pose(foot).basis
	skeleton.set_bone_pose_rotation(foot, (parent_basis.orthonormalized().inverse() * turned.orthonormalized()).get_rotation_quaternion())
