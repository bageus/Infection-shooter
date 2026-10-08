extends SkeletonModifier3D
## Fits the supporting hand to the new kit; minigun uses a low two-arm pose.
const BACKPACK := preload("res://models/objects/weapons/minigun_ammo_backpack_lowpoly.glb")
var mount: Node
var backpack: Node3D
var _back_attachment: BoneAttachment3D
var capture_pose := false
var posed_bones: Array[Transform3D] = []
var hand_error := 0.0
var arm_geometry: Dictionary = {}


func _ready() -> void:
	var skeleton := get_skeleton()
	_back_attachment = BoneAttachment3D.new()
	_back_attachment.name = "MinigunBackAttachment"
	_back_attachment.bone_name = "Spine"
	skeleton.add_child(_back_attachment)
	backpack = BACKPACK.instantiate() as Node3D
	backpack.name = "MinigunBackpack"
	_back_attachment.add_child(backpack)
	backpack.rotation.y = PI
	backpack.position = Vector3(0, .10, -.23)
	backpack.hide()


func _process_modification_with_delta(_delta: float) -> void:
	var weapon := mount.get("_active") as Node3D
	if not is_instance_valid(weapon):
		return
	var name_value: String = weapon.call("get_weapon_name")
	backpack.visible = name_value == "MINIGUN"
	if name_value not in ["AK", "M4", "SNIPER RIFLE", "MINIGUN"]:
		return
	var skeleton := get_skeleton()
	var socket_offset: Transform3D = mount.get("_socket_offset")
	var reference_weapon := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).basis * socket_offset.basis
	var support_orientation := reference_weapon.inverse() * skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).basis
	mount.set("_aim_modifying", true)
	# Skeleton space: +Z front. Keep the rear hand near the body so both
	# arms can reach the new, longer kit without stretching bones.
	var target_right := Vector3(-.27, .23, .08) if name_value == "MINIGUN" else Vector3(-.13, .43, .07)
	_fit_arm(skeleton, "Right", target_right, Vector3(-.65, .15, .10))
	_level_right_hand(skeleton)
	mount.call("sync_weapon", weapon)
	var left_grip := weapon.find_child("Grip_L", true, false) as Node3D
	if left_grip != null:
		var target := skeleton.to_local(left_grip.global_position)
		_fit_arm(skeleton, "Left", target, Vector3(.65, .20, .15))
		_set_hand_basis(skeleton, "Left", skeleton.global_basis.inverse() * weapon.global_basis * support_orientation)
		_curl_support_hand(skeleton, target, skeleton.global_basis.inverse() * weapon.global_basis)
		hand_error = skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin.distance_to(target)
	mount.call("sync_weapon", weapon)
	if capture_pose:
		posed_bones.clear()
		for bone in skeleton.get_bone_count():
			posed_bones.append(skeleton.get_bone_global_pose(bone))
	mount.set("_aim_modifying", false)


func _fit_arm(skeleton: Skeleton3D, side: String, target: Vector3, pole: Vector3) -> void:
	var upper := skeleton.find_bone(side + "Arm")
	var lower := skeleton.find_bone(side + "ForeArm")
	var hand := skeleton.find_bone(side + "Hand")
	if mini(upper, mini(lower, hand)) < 0:
		return
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow := skeleton.get_bone_global_pose(lower).origin
	var wrist := skeleton.get_bone_global_pose(hand).origin
	var a := shoulder.distance_to(elbow)
	var b := elbow.distance_to(wrist)
	if capture_pose:
		arm_geometry[side] = [shoulder, a, b, shoulder.distance_to(target)]
	var direction := (target - shoulder).normalized()
	var distance := clampf(shoulder.distance_to(target), absf(a - b) + .001, a + b - .001)
	var bend := pole - shoulder
	bend = (bend - direction * bend.dot(direction)).normalized()
	if bend.is_zero_approx():
		bend = direction.cross(Vector3.UP).normalized()
	var along := (a * a + distance * distance - b * b) / (2.0 * distance)
	var height := sqrt(maxf(0.0, a * a - along * along))
	var desired_elbow := shoulder + direction * along + bend * height
	_turn_bone(skeleton, upper, elbow - shoulder, desired_elbow - shoulder)
	elbow = skeleton.get_bone_global_pose(lower).origin
	wrist = skeleton.get_bone_global_pose(hand).origin
	_turn_bone(skeleton, lower, wrist - elbow, shoulder + direction * distance - elbow)


func _turn_bone(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.is_zero_approx() or to.is_zero_approx():
		return
	var pose := skeleton.get_bone_global_pose(bone)
	var desired := Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion())


func _level_right_hand(skeleton: Skeleton3D) -> void:
	var socket_offset: Transform3D = mount.get("_socket_offset")
	var barrel := Vector3(.30, 0, sqrt(.91))
	var weapon_basis := Basis(barrel, Vector3.DOWN, barrel.cross(Vector3.DOWN))
	var hand_basis := weapon_basis * socket_offset.basis.inverse()
	_set_hand_basis(skeleton, "Right", hand_basis)


func _set_hand_basis(skeleton: Skeleton3D, side: String, basis: Basis) -> void:
	var hand := skeleton.find_bone(side + "Hand")
	var parent := skeleton.get_bone_parent(hand)
	var local := skeleton.get_bone_global_pose(parent).basis.inverse() * basis
	skeleton.set_bone_pose_rotation(hand, local.orthonormalized().get_rotation_quaternion())


func _curl_support_hand(skeleton: Skeleton3D, grip: Vector3, weapon_basis: Basis) -> void:
	# Fingers wrap over the supporting grip instead of staying open above it.
	var fingers := ["Index", "Middle", "Ring", "Pinky"]
	for i in fingers.size():
		var first := skeleton.find_bone("Left" + fingers[i] + "1")
		var second := skeleton.find_bone("Left" + fingers[i] + "2")
		var end := skeleton.find_bone("Left" + fingers[i] + "End")
		if mini(first, mini(second, end)) < 0:
			continue
		var along := weapon_basis.x * ((float(i) - 1.5) * .018)
		var knuckle := grip + along - weapon_basis.y * .045
		var tip := grip + along - weapon_basis.y * .02 - weapon_basis.z * .04
		var base := skeleton.get_bone_global_pose(first).origin
		_turn_bone(skeleton, first, skeleton.get_bone_global_pose(second).origin - base, knuckle - base)
		var joint := skeleton.get_bone_global_pose(second).origin
		_turn_bone(skeleton, second, skeleton.get_bone_global_pose(end).origin - joint, tip - joint)
