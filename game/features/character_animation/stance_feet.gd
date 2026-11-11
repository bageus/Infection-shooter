extends SkeletonModifier3D
## Idle stance: the rear (left) foot of the clip points outward; turn it towards the centre.
## Walking: the clips leave the knee turned inward while the foot points outward;
## twist thigh and foot about their axes until both face the front.
## Presentation only.

const TURN_DEGREES := 30.0
const BLEND_PER_SECOND := 8.0

var player: AnimationPlayer
const MAX_WALK_TWIST := deg_to_rad(40.0)
var _amount := 0.0
var _walk_amount := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	var foot := skeleton.find_bone("LeftFoot") if skeleton != null else -1
	var leg := skeleton.find_bone("LeftLeg") if skeleton != null else -1
	if foot < 0 or leg < 0 or player == null:
		return
	var clip := String(player.current_animation)
	_walk_amount = move_toward(_walk_amount, 1.0 if clip.begins_with("Walk") or clip.begins_with("Run") else 0.0, BLEND_PER_SECOND * delta)
	if _walk_amount > 0.0:
		for side in ["Left", "Right"]:
			_straighten_leg(skeleton, side)
	# The lowered-pistol idle already has both feet straight; turning the left one bends the leg inward.
	var idle := clip.begins_with("Idle") and not clip.begins_with("Idle_Pistol_Down")
	_amount = move_toward(_amount, 1.0 if idle else 0.0, BLEND_PER_SECOND * delta)
	if _amount <= 0.0:
		return
	var shin := skeleton.get_bone_global_pose(foot).origin - skeleton.get_bone_global_pose(leg).origin
	var parent := skeleton.get_bone_parent(foot)
	var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var turn := Quaternion(shin.normalized(), deg_to_rad(TURN_DEGREES) * _amount)
	skeleton.set_bone_pose_rotation(foot, (parent_rotation.inverse() * turn * parent_rotation * skeleton.get_bone_pose_rotation(foot)).normalized())


## Twists the thigh, then the foot, about their own axes until the knee and the toes face the body's front.
func _straighten_leg(skeleton: Skeleton3D, side: String) -> void:
	var hip := skeleton.find_bone(side + "UpLeg")
	var knee := skeleton.find_bone(side + "Leg")
	var foot := skeleton.find_bone(side + "Foot")
	if mini(hip, mini(knee, foot)) < 0:
		return
	var thigh := (skeleton.get_bone_global_pose(knee).origin - skeleton.get_bone_global_pose(hip).origin).normalized()
	_twist(skeleton, hip, thigh, _facing(skeleton, knee))
	var shin := (skeleton.get_bone_global_pose(foot).origin - skeleton.get_bone_global_pose(knee).origin).normalized()
	_twist(skeleton, foot, shin, _facing(skeleton, foot))


## Skeleton-space direction the bone's front axis (the one that points forward at rest) faces now.
func _facing(skeleton: Skeleton3D, bone: int) -> Vector3:
	var rest := skeleton.get_bone_global_rest(bone).basis
	return skeleton.get_bone_global_pose(bone).basis * (rest.inverse() * Vector3.BACK).normalized()


func _twist(skeleton: Skeleton3D, bone: int, axis: Vector3, facing: Vector3) -> void:
	var from := facing - axis * facing.dot(axis)
	var to := Vector3.BACK - axis * Vector3.BACK.dot(axis)
	if from.length_squared() < 0.0001 or to.length_squared() < 0.0001:
		return
	var cross := from.cross(to)
	var angle := clampf(from.angle_to(to) * signf(cross.dot(axis)), -MAX_WALK_TWIST, MAX_WALK_TWIST) * _walk_amount
	var parent_rotation := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone)).basis.get_rotation_quaternion()
	var turn := Quaternion(axis, angle)
	skeleton.set_bone_pose_rotation(bone, (parent_rotation.inverse() * turn * parent_rotation * skeleton.get_bone_pose_rotation(bone)).normalized())


## Adds the modifier to the model's first skeleton when it has a left foot (soldier rig only).
static func attach(model: Node, animation_player: AnimationPlayer) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or (skeletons[0] as Skeleton3D).find_bone("LeftFoot") < 0:
		return
	var feet: Node = (load("res://game/features/character_animation/stance_feet.gd") as GDScript).new()
	feet.name = "StanceFeet"
	feet.set("player", animation_player)
	(skeletons[0] as Node).add_child(feet)
