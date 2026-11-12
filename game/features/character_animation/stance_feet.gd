extends SkeletonModifier3D
## Idle stance: the rear (left) foot of the clip points outward; turn it towards the centre.
## Walking: the clips swing the knees slightly outward; shift each knee a little towards the body's centre
## (hip and foot stay where the clip put them).
## Presentation only.

const TURN_DEGREES := 30.0
const BLEND_PER_SECOND := 8.0

var player: AnimationPlayer
## Metres the knee moves towards the body's centre line while walking or running.
const KNEE_IN := 0.03
## Below this knee offset (m) the leg is too straight for a knee direction.
const MIN_BEND := 0.03
var _amount := 0.0
var _walk_amount := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	var foot := skeleton.find_bone("LeftFoot") if skeleton != null else -1
	var leg := skeleton.find_bone("LeftLeg") if skeleton != null else -1
	if foot < 0 or leg < 0 or player == null:
		return
	var clip := String(player.current_animation)
	_walk_amount = move_toward(_walk_amount, 1.0 if clip.begins_with("Walk_") else 0.0, BLEND_PER_SECOND * delta)
	# Gait and leg clips already set the knees; only the bare authored Walk_* legs need the nudge.
	if _walk_amount > 0.0 and skeleton.get_node_or_null("ProceduralGait") == null and skeleton.get_node_or_null("LegClips") == null:
		_nudge_knee_in(skeleton, "Left")
		_nudge_knee_in(skeleton, "Right")
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


func _nudge_knee_in(skeleton: Skeleton3D, side: String) -> void:
	var hip := skeleton.find_bone(side + "UpLeg")
	var knee := skeleton.find_bone(side + "Leg")
	var foot := skeleton.find_bone(side + "Foot")
	if mini(hip, mini(knee, foot)) < 0:
		return
	var hip_at := skeleton.get_bone_global_pose(hip).origin
	var knee_at := skeleton.get_bone_global_pose(knee).origin
	var foot_pose := skeleton.get_bone_global_pose(foot)
	var line := foot_pose.origin - hip_at
	if line.length_squared() < 0.0001:
		return
	var axis := line.normalized()
	var bend := (knee_at - hip_at) - axis * (knee_at - hip_at).dot(axis)
	if bend.length() < MIN_BEND:
		return
	var moved := knee_at + Vector3(-signf(hip_at.x), 0.0, 0.0) * KNEE_IN * _walk_amount - hip_at
	var direction := (moved - axis * moved.dot(axis)).normalized()
	var upper := (knee_at - hip_at).length()
	var lower := (foot_pose.origin - knee_at).length()
	var distance := clampf(line.length(), absf(upper - lower) + .001, upper + lower - .001)
	var along := (upper * upper + distance * distance - lower * lower) / (2.0 * distance)
	var desired := hip_at + axis * along + direction * sqrt(maxf(0.0, upper * upper - along * along))
	_turn_bone(skeleton, hip, knee_at - hip_at, desired - hip_at)
	var moved_knee := skeleton.get_bone_global_pose(knee).origin
	_turn_bone(skeleton, knee, skeleton.get_bone_global_pose(foot).origin - moved_knee, hip_at + axis * distance - moved_knee)
	# The foot keeps the orientation the clip gave it.
	var parent_basis := skeleton.get_bone_global_pose(skeleton.get_bone_parent(foot)).basis
	skeleton.set_bone_pose_rotation(foot, (parent_basis.inverse() * foot_pose.basis).orthonormalized().get_rotation_quaternion())


func _turn_bone(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.is_zero_approx() or to.is_zero_approx():
		return
	var pose := skeleton.get_bone_global_pose(bone)
	var desired := Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion())


## Adds the modifier to the model's first skeleton when it has a left foot (soldier rig only).
static func attach(model: Node, animation_player: AnimationPlayer) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or (skeletons[0] as Skeleton3D).find_bone("LeftFoot") < 0:
		return
	var feet: Node = (load("res://game/features/character_animation/stance_feet.gd") as GDScript).new()
	feet.name = "StanceFeet"
	feet.set("player", animation_player)
	(skeletons[0] as Node).add_child(feet)
