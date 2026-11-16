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
	"PISTOL": {"RightForeArm": 5.0, "LeftForeArm": 4.0, "RightHand": 10.0, "LeftHand": 8.0},
	"UZI": {"RightForeArm": 3.5, "LeftForeArm": 3.0, "RightHand": 7.0, "LeftHand": 6.0},
	"AK": {"RightShoulder": 4.0, "LeftShoulder": 4.0, "RightForeArm": 4.0, "LeftForeArm": 4.0, "RightHand": 6.0, "LeftHand": 6.0},
	"M4": {"RightShoulder": 3.5, "LeftShoulder": 3.5, "RightForeArm": 3.5, "LeftForeArm": 3.5, "RightHand": 5.0, "LeftHand": 5.0},
	"SHOTGUN": {"Spine": 3.0, "Spine2": 6.0, "RightForeArm": 3.0, "LeftForeArm": 3.0, "RightHand": 5.0, "LeftHand": 5.0},
	"SNIPER RIFLE": {"Spine": 2.5, "Spine2": 5.0, "RightForeArm": 2.5, "LeftForeArm": 2.5, "RightHand": 4.0, "LeftHand": 4.0},
	"GRENADE LAUNCHER": {"Spine": 3.0, "Spine2": 6.0, "RightForeArm": 3.0, "LeftForeArm": 3.0, "RightHand": 5.0, "LeftHand": 5.0},
	"MINIGUN": {"RightShoulder": 2.5, "LeftShoulder": 2.5, "RightForeArm": 3.0, "LeftForeArm": 3.0},
}
## The shot's kick fades in 0.08 s, too brief to see from the camera; the pose holds it about this long.
const RECOIL_HOLD_SECONDS := 0.14
var mount: Node
var _lean := 0.0
var _recoil := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or mount == null:
		return
	_apply_lean(skeleton, delta)
	var shot: Object = mount.get("recoil")
	_recoil = maxf(float(shot.get("kick")) if shot != null else 0.0, _recoil * exp(-delta / RECOIL_HOLD_SECONDS))
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
	if recoil == null or _recoil < 0.001 or muzzle == null:
		return
	var forward := -muzzle.global_basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		return
	var axis := forward.normalized().cross(Vector3.UP)
	var profile: Dictionary = RECOIL.get(String(weapon.call("get_weapon_name")), {})
	for bone_name: String in profile:
		_pitch(skeleton, bone_name, axis, deg_to_rad(float(profile[bone_name])) * _recoil)


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
