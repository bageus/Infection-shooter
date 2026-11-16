extends SkeletonModifier3D
## Upper-body motion drawn over the baked clips: a forward lean while running, and a micro-kick on a shot.
## The kick is per weapon: the heavier the gun, the more of the body takes it (pistol and uzi only hands and elbows,
## rifles add the shoulders, shotgun and sniper a little of the torso, minigun elbows and shoulders).

## Forward lean of the spine at a full run, degrees; the shoulders turn back by the same amount so the arms keep
## their aim and the gun does not point down.
const LEAN_DEGREES := 10.0
const LEAN_SPINE := {"Spine": 0.4, "Spine1": 0.3, "Spine2": 0.3}
const LEAN_START_SPEED := 1.8
const LEAN_FULL_SPEED := 4.0
const LEAN_FOLLOW := 8.0
## Degrees of muzzle-rise pitch per bone at full kick, listed from the spine outwards (parents first).
const RECOIL := {
	"PISTOL": {"RightForeArm": 1.5, "LeftForeArm": 1.5, "RightHand": 4.0, "LeftHand": 3.0},
	"UZI": {"RightForeArm": 1.2, "LeftForeArm": 1.2, "RightHand": 3.0, "LeftHand": 2.5},
	"AK": {"RightShoulder": 1.5, "LeftShoulder": 1.5, "RightForeArm": 1.5, "LeftForeArm": 1.5, "RightHand": 2.5, "LeftHand": 2.5},
	"M4": {"RightShoulder": 1.2, "LeftShoulder": 1.2, "RightForeArm": 1.2, "LeftForeArm": 1.2, "RightHand": 2.0, "LeftHand": 2.0},
	"SHOTGUN": {"Spine": 1.0, "Spine2": 2.5, "RightForeArm": 1.0, "LeftForeArm": 1.0, "RightHand": 1.5, "LeftHand": 1.5},
	"SNIPER RIFLE": {"Spine": 0.8, "Spine2": 2.0, "RightForeArm": 0.8, "LeftForeArm": 0.8, "RightHand": 1.2, "LeftHand": 1.2},
	"GRENADE LAUNCHER": {"Spine": 1.0, "Spine2": 2.5, "RightForeArm": 1.0, "LeftForeArm": 1.0, "RightHand": 1.5, "LeftHand": 1.5},
	"MINIGUN": {"RightShoulder": 1.0, "LeftShoulder": 1.0, "RightForeArm": 1.2, "LeftForeArm": 1.2},
}
var mount: Node
var _lean := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or mount == null:
		return
	_apply_lean(skeleton, delta)
	_apply_recoil(skeleton)


func _apply_lean(skeleton: Skeleton3D, delta: float) -> void:
	var body := mount.get_parent() as CharacterBody3D
	var driver: Node = mount.get("_driver")
	var velocity := Vector3(body.velocity.x, 0.0, body.velocity.z) if body != null else Vector3.ZERO
	var rolling: bool = driver != null and bool(driver.call("is_dodging"))
	var target := 0.0 if rolling else clampf((velocity.length() - LEAN_START_SPEED) / (LEAN_FULL_SPEED - LEAN_START_SPEED), 0.0, 1.0)
	_lean = lerpf(_lean, target, 1.0 - exp(-LEAN_FOLLOW * delta))
	if _lean < 0.001 or velocity.is_zero_approx():
		return
	var axis := velocity.normalized().cross(Vector3.UP)
	var angle := -deg_to_rad(LEAN_DEGREES) * _lean
	for bone_name: String in LEAN_SPINE:
		_pitch(skeleton, bone_name, axis, angle * float(LEAN_SPINE[bone_name]))
	for bone_name in ["LeftShoulder", "RightShoulder"]:
		_pitch(skeleton, bone_name, axis, -angle)
	_pitch(skeleton, "Neck", axis, -angle * 0.5)


func _apply_recoil(skeleton: Skeleton3D) -> void:
	var recoil: Object = mount.get("recoil")
	var weapon := mount.get("_active") as Node3D
	var muzzle := weapon.get_node_or_null("Muzzle") as Node3D if is_instance_valid(weapon) else null
	if recoil == null or float(recoil.get("kick")) <= 0.0 or muzzle == null:
		return
	var forward := -muzzle.global_basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		return
	var axis := forward.normalized().cross(Vector3.UP)
	var profile: Dictionary = RECOIL.get(String(weapon.call("get_weapon_name")), {})
	for bone_name: String in profile:
		_pitch(skeleton, bone_name, axis, deg_to_rad(float(profile[bone_name])) * float(recoil.get("kick")))


# Turns a bone about a world-space axis through its joint, keeping its parent's pose.
func _pitch(skeleton: Skeleton3D, bone_name: String, axis: Vector3, angle: float) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0 or axis.is_zero_approx():
		return
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var world := skeleton.global_basis * skeleton.get_bone_global_pose(bone).basis
	var turned := Basis(axis.normalized(), angle) * world
	var local := parent_basis.inverse() * skeleton.global_basis.inverse() * turned
	skeleton.set_bone_pose_rotation(bone, local.orthonormalized().get_rotation_quaternion())
