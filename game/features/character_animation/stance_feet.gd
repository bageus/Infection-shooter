extends SkeletonModifier3D
## Idle stance: the rear (left) foot of the clip points outward; turn it towards the centre.
## Presentation only. Walk and run clips keep their feet.

const TURN_DEGREES := 30.0
const BLEND_PER_SECOND := 8.0

var player: AnimationPlayer
var _amount := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	var foot := skeleton.find_bone("LeftFoot") if skeleton != null else -1
	var leg := skeleton.find_bone("LeftLeg") if skeleton != null else -1
	if foot < 0 or leg < 0 or player == null:
		return
	var idle := String(player.current_animation).begins_with("Idle")
	_amount = move_toward(_amount, 1.0 if idle else 0.0, BLEND_PER_SECOND * delta)
	if _amount <= 0.0:
		return
	var shin := skeleton.get_bone_global_pose(foot).origin - skeleton.get_bone_global_pose(leg).origin
	var parent := skeleton.get_bone_parent(foot)
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var turn := Quaternion(shin.normalized(), deg_to_rad(TURN_DEGREES) * _amount)
	skeleton.set_bone_pose_rotation(foot, (parent_rotation.inverse() * turn * parent_rotation * skeleton.get_bone_pose_rotation(foot)).normalized())


## Adds the modifier to the model's first skeleton when it has a left foot (soldier rig only).
static func attach(model: Node, animation_player: AnimationPlayer) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or (skeletons[0] as Skeleton3D).find_bone("LeftFoot") < 0:
		return
	var feet: Node = (load("res://game/features/character_animation/stance_feet.gd") as GDScript).new()
	feet.name = "StanceFeet"
	feet.set("player", animation_player)
	(skeletons[0] as Node).add_child(feet)
