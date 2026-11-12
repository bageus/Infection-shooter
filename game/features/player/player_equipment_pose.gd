extends SkeletonModifier3D
## Fits the supporting hand to the new kit; minigun uses a low two-arm pose.
const BACKPACK := preload("res://models/objects/weapons/minigun_ammo_backpack_lowpoly.glb")
## Rear hand of the minigun in skeleton space: belt height, gripped from above.
const MINIGUN_RIGHT_HAND := Vector3(-.22, -.02, .14)
## Long guns are scaled to the character and gripped near the chest: scale, then the rear hand in skeleton space.
## Their forend must stay within reach of the support arm (about .55 m from the left shoulder).
const LONG_GUN := {
	"AK": [.74, Vector3(-.165, .41, .77)],
	"M4": [.74, Vector3(-.165, .41, .77)],
	"SNIPER RIFLE": [.70, Vector3(-.145, .39, .22)],
	"SHOTGUN": [.79, Vector3(-.145, .415, .505)],
	"GRENADE LAUNCHER": [.87, Vector3(-.085, .415, .725)],
}
## Short guns have grips so close together that both hands collide: the forend hand holds this much further along the barrel (weapon units).
const FOREND_REACH := {"SHOTGUN": .045, "GRENADE LAUNCHER": -.18, "SNIPER RIFLE": -.075, "AK": -.055, "M4": -.055}
## Extra arm posing per weapon, set by hand in tools/weapon_hold_tuner.tscn: joint turns in degrees
## (bone -> Vector3) and hand nudges in skeleton space (side -> Vector3).
const ARM_TUNING := {
	"SNIPER RIFLE": {
		"bones": {"RightArm": Vector3(-9, 28, 0), "RightForeArm": Vector3(-3, -22, 15), "RightHand": Vector3(-5, 8, -9), "LeftArm": Vector3(0, 22, 10), "LeftForeArm": Vector3(-6, -64, 11), "LeftHand": Vector3(-42, -15, 19)},
		"hands": {"Right": Vector3(-.11, -.03, .06), "Left": Vector3(.045, .165, .055)},
	},
	"GRENADE LAUNCHER": {
		"bones": {"RightArm": Vector3(-9, 28, 0), "RightForeArm": Vector3(-3, -22, 15), "RightHand": Vector3(-5, 8, -9), "LeftArm": Vector3(0, 22, 10), "LeftForeArm": Vector3(-6, -64, 11), "LeftHand": Vector3(-21, 90, -33)},
		"hands": {"Right": Vector3(-.11, -.03, .06), "Left": Vector3(-.125, .14, -.045)},
	},
	"SHOTGUN": {
		"bones": {"RightArm": Vector3(-7, 50, -3), "RightForeArm": Vector3(3, -8, 16), "RightHand": Vector3(-11, -3, -4), "LeftArm": Vector3(0, 22, 10), "LeftForeArm": Vector3(-6, -40, 6), "LeftHand": Vector3(-21, 37, -39)},
		"hands": {"Right": Vector3(-.04, .085, .015), "Left": Vector3(-.105, .065, .06)},
	},
	"AK": {
		"bones": {"RightArm": Vector3(-7, 10, 0), "RightForeArm": Vector3(-10, -9, 3), "RightHand": Vector3(-5, -5, -9), "LeftArm": Vector3(4, 9, 10)},
		"hands": {"Right": Vector3(-.065, -.115, -.23)},
	},
	"M4": {
		"bones": {"RightArm": Vector3(-7, 10, 0), "RightForeArm": Vector3(-10, -9, 3), "RightHand": Vector3(-5, -5, -9), "LeftArm": Vector3(4, 9, 10)},
		"hands": {"Right": Vector3(-.065, -.115, -.23)},
	},
}
## Live overrides for the hold tuner (tools/weapon_hold_tuner.tscn): weapon name -> [scale, rear hand, forend reach].
var tuning := {}
## Hand position nudges for the tuner: "Right"/"Left" -> Vector3 in skeleton space.
var hand_offset := {}
## The tuner sets this to drive the arm nudges and bone turns itself instead of ARM_TUNING.
var manual_arms := false
var _held := ""
var mount: Node
var backpack: Node3D
var _back_attachment: BoneAttachment3D
var capture_pose := false
var posed_bones: Array[Transform3D] = []
var hand_error := 0.0
## Distance of the right hand from the forend on long guns.
var forend_error := 0.0
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
	# Small white emissive markers (helmet, knees, vest) outline the hero in dark rooms without lighting the scene.
	# shortcut: marker offsets are set by eye on the authored bones, re-check them when the hero model changes.
	var dot := SphereMesh.new()
	dot.radius = .035
	dot.height = .07
	dot.material = StandardMaterial3D.new()
	dot.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material.albedo_color = Color.WHITE
	dot.material.emission_enabled = true
	dot.material.emission = Color.WHITE
	dot.material.emission_energy_multiplier = 2.0
	for spot in [["Head", Vector3(0, .1, -.17)], ["Head", Vector3(0, .1, .15)], ["LeftLeg", Vector3(0, 0, .14)], ["RightLeg", Vector3(0, 0, .14)], ["Spine2", Vector3(0, .05, .2)], ["Spine2", Vector3(0, .05, -.2)]]:
		var attach := BoneAttachment3D.new()
		attach.bone_name = spot[0]
		skeleton.add_child(attach)
		var marker := MeshInstance3D.new()
		marker.name = "GlowMarker"
		marker.mesh = dot
		marker.position = spot[1]
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attach.add_child(marker)


func _process_modification_with_delta(_delta: float) -> void:
	var weapon := mount.get("_active") as Node3D
	if not is_instance_valid(weapon):
		return
	var name_value: String = weapon.call("get_weapon_name")
	_held = name_value
	backpack.visible = name_value == "MINIGUN"
	var full_kit := name_value in LONG_GUN or name_value == "MINIGUN"
	mount.set("grip_shift", Vector3.ZERO)
	if not full_kit:
		return
	if name_value in LONG_GUN:
		weapon.scale = Vector3.ONE * float(_spec(name_value)[0])
	var skeleton := get_skeleton()
	var socket_offset: Transform3D = mount.get("_socket_offset")
	var reference_weapon := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).basis * socket_offset.basis
	var support_orientation := reference_weapon.inverse() * skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).basis
	mount.set("_aim_modifying", true)
	# Skeleton space: +Z front. Keep the rear hand near the body so both
	# arms can reach the new, longer kit without stretching bones.
	# Rifle stocks extend behind the rear hand, so the hand sits ahead of the
	# chest; the sniper's longer stock needs a little more clearance.
	var target_right: Vector3 = MINIGUN_RIGHT_HAND if name_value == "MINIGUN" else _spec(name_value)[1]
	# Long guns are held with the right hand on the forend and the left on the trigger grip.
	# The weapon stays where it was: the right hand goes to the forend, the left to the old rear grip.
	var left_grip := weapon.find_child("Grip_L", true, false) as Node3D
	if name_value in LONG_GUN:
		var rear := _grip_local(weapon, weapon.find_child("Grip_R", true, false) as Node3D)
		var fore := _grip_local(weapon, left_grip) + Vector3.RIGHT * float(_spec(name_value)[2]) * weapon.scale.x
		mount.set("grip_shift", -fore)
		target_right += _barrel_basis() * (fore - rear)
		left_grip = weapon.find_child("Grip_R", true, false) as Node3D
	_fit_arm(skeleton, "Right", target_right, Vector3(-.65, .15, .10))
	_level_right_hand(skeleton)
	mount.call("sync_weapon", weapon)
	if left_grip != null:
		var target := skeleton.to_local(left_grip.global_position)
		if name_value in LONG_GUN:
			# The trigger hand holds the grip like the right hand does, mirrored: the palm, not the wrist, sits on the grip.
			var mirror := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3.BACK)
			var hand_basis := _barrel_basis() * (mirror * socket_offset.basis * mirror).inverse()
			var wrist := target - hand_basis * (mirror * socket_offset.origin)
			_fit_arm(skeleton, "Left", wrist, Vector3(.65, .20, .15))
			_set_hand_basis(skeleton, "Left", hand_basis)
			hand_error = skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin.distance_to(wrist)
		else:
			_fit_arm(skeleton, "Left", target, Vector3(.65, .20, .15))
			_set_hand_basis(skeleton, "Left", skeleton.global_basis.inverse() * weapon.global_basis * support_orientation)
			_curl_support_hand(skeleton, target, skeleton.global_basis.inverse() * weapon.global_basis)
			hand_error = skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin.distance_to(target)
	mount.call("sync_weapon", weapon)
	if name_value in LONG_GUN:
		forend_error = (skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")) * socket_offset).origin.distance_to(skeleton.to_local(weapon.find_child("Grip_L", true, false).global_position + weapon.global_basis.orthonormalized().x * float(_spec(name_value)[2]) * weapon.scale.x))
	if capture_pose:
		posed_bones.clear()
		for bone in skeleton.get_bone_count():
			posed_bones.append(skeleton.get_bone_global_pose(bone))
	mount.set("_aim_modifying", false)


## Scale, rear-hand point and forend reach of a long gun, from the tuner when it overrides them.
## Hand nudge for a side: the tuner's slider in manual mode, otherwise the weapon's ARM_TUNING.
func _nudge(side: String) -> Vector3:
	return hand_offset.get(side, Vector3.ZERO) if manual_arms else ARM_TUNING.get(_held, {}).get("hands", {}).get(side, Vector3.ZERO)


## Bone turns for the held weapon, in degrees.
func arm_bones() -> Dictionary:
	return ARM_TUNING.get(_held, {}).get("bones", {})


func _spec(weapon_name: String) -> Array:
	if tuning.has(weapon_name):
		return tuning[weapon_name]
	return [LONG_GUN[weapon_name][0], LONG_GUN[weapon_name][1], FOREND_REACH.get(weapon_name, 0.0)]


func _fit_arm(skeleton: Skeleton3D, side: String, target: Vector3, pole: Vector3) -> void:
	target += _nudge(side)
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
	_set_hand_basis(skeleton, "Right", _barrel_basis() * socket_offset.basis.inverse())


func _barrel_basis() -> Basis:
	var barrel := Vector3(.30, 0, sqrt(.91))
	return Basis(barrel, Vector3.DOWN, barrel.cross(Vector3.DOWN))


## Marker position in the weapon's own frame, with the weapon's scale applied.
func _grip_local(weapon: Node3D, marker: Node3D) -> Vector3:
	return (weapon.global_transform.affine_inverse() * marker.global_position) * weapon.scale.x


func _set_hand_basis(skeleton: Skeleton3D, side: String, hand_basis: Basis) -> void:
	var hand := skeleton.find_bone(side + "Hand")
	var parent := skeleton.get_bone_parent(hand)
	var local := skeleton.get_bone_global_pose(parent).basis.inverse() * hand_basis
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
