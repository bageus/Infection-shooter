extends SkeletonModifier3D
## Procedural melee strike layered over the playing clip (ADR-0066): a push
## kick with the right leg or a jab with the left arm. Each limb bone is aimed
## along keyframed skeleton-space directions (wind-up, strike, recovery) and
## blended in and out, so everything else keeps its clip. The kick chambers the
## knee high, drives the sole forward with the hips behind it while the torso
## leans back and the standing leg braces, then re-chambers and sets the foot
## down. Front is +Z, up +Y. Presentation only.

const KICK := &"kick"
const PUNCH := &"punch"
const KICK_SECONDS := 0.65
const PUNCH_SECONDS := 0.4
## Seconds from the start to the moment the foot or fist lands.
const KICK_IMPACT := 0.27
const PUNCH_IMPACT := 0.14

# Limb tracks: bone -> [child bone (gives the bone's direction), keys]; a key is
# [time share, skeleton-space direction the bone points along].
const KICK_TRACKS := {
	"RightUpLeg": ["RightLeg", [[0.0, Vector3(0, -1, 0)], [0.3, Vector3(0, 0.5, 1.0)], [0.42, Vector3(0, 0.15, 1.0)], [0.52, Vector3(0, 0.15, 1.0)], [0.72, Vector3(0, 0.4, 1.0)], [1.0, Vector3(0, -1, 0)]]],
	"RightLeg": ["RightFoot", [[0.0, Vector3(0, -1, 0)], [0.3, Vector3(0, -1.0, -0.35)], [0.42, Vector3(0, 0.1, 1.0)], [0.52, Vector3(0, 0.1, 1.0)], [0.72, Vector3(0, -1.0, -0.3)], [1.0, Vector3(0, -1, 0)]]],
	# Toes pull up at the strike so the sole, not the toes, pushes forward.
	"RightFoot": ["RightToeBase", [[0.0, Vector3(0, -0.45, 0.9)], [0.3, Vector3(0, -0.15, 1.0)], [0.42, Vector3(0, 1.0, 0.3)], [0.52, Vector3(0, 1.0, 0.3)], [0.72, Vector3(0, -0.15, 1.0)], [1.0, Vector3(0, -0.45, 0.9)]]],
}
## Kick drive keys [time share, 0..1]: how far the hips have pushed in behind the sole.
const KICK_DRIVE := [[0.0, 0.0], [0.3, 0.25], [0.42, 1.0], [0.52, 1.0], [0.72, 0.3], [1.0, 0.0]]
## Hips shift at full drive, as a share of the kicking leg's length (forward, slightly down).
const KICK_HIPS_SHIFT := Vector3(0.0, -0.03, 0.16)
## Standing leg turn (degrees about skeleton X; positive swings the foot back) at full
## drive: the thigh tilts back under the shifted hips and the knee softens.
const KICK_BRACE := {"LeftUpLeg": 9.0, "LeftLeg": 5.0}
const PUNCH_TRACKS := {
	"LeftArm": ["LeftForeArm", [[0.0, Vector3(0.6, -0.8, 0.3)], [0.3, Vector3(0.6, -0.4, -0.6)], [0.5, Vector3(0.12, 0.05, 1.0)], [0.65, Vector3(0.12, 0.05, 1.0)], [1.0, Vector3(0.6, -0.8, 0.3)]]],
	"LeftForeArm": ["LeftWrist", [[0.0, Vector3(0.3, -0.5, 0.8)], [0.3, Vector3(0.2, 0.3, 0.9)], [0.5, Vector3(0.1, 0.05, 1.0)], [0.65, Vector3(0.1, 0.05, 1.0)], [1.0, Vector3(0.3, -0.5, 0.8)]]],
}
# Torso lean/twist (degrees about skeleton axes) at the strike moment, scaled by the envelope.
const KICK_TORSO := Vector3(-18.0, 0.0, 0.0)
const PUNCH_TORSO := Vector3(-3.0, -14.0, 0.0)
const TORSO_BONES := ["Spine1", "Spine2"]
## Share of the blend that is in full effect: ramps in over the first 15 % and out over the last 25 %.
const RAMP_IN := 0.15
const RAMP_OUT := 0.25

var _kind: StringName = &""
var _elapsed := 0.0
var _duration := 0.0


## Starts a strike; returns its duration, 0.0 when the skeleton lacks the bones.
func start(kind: StringName) -> float:
	var skeleton := get_skeleton()
	var tracks := _tracks(kind)
	if skeleton == null or tracks.is_empty():
		return 0.0
	for bone_name: String in tracks:
		if skeleton.find_bone(bone_name) < 0 or skeleton.find_bone(tracks[bone_name][0]) < 0:
			return 0.0
	_kind = kind
	_elapsed = 0.0
	_duration = KICK_SECONDS if kind == KICK else PUNCH_SECONDS
	return _duration


func is_playing() -> bool:
	return _kind != &""


func stop() -> void:
	_kind = &""


## Direction `bone` points along at time share `t` of `kind`; zero for a bone the strike leaves alone.
static func direction_at(kind: StringName, bone: String, t: float) -> Vector3:
	var tracks := _tracks(kind)
	if not tracks.has(bone):
		return Vector3.ZERO
	var keys: Array = tracks[bone][1]
	for index in range(1, keys.size()):
		var next: Array = keys[index]
		if t <= float(next[0]):
			var previous: Array = keys[index - 1]
			var span := float(next[0]) - float(previous[0])
			var k := 0.0 if span <= 0.0 else (t - float(previous[0])) / span
			k = k * k * (3.0 - 2.0 * k)
			return (previous[1] as Vector3).lerp(next[1], k).normalized()
	return (keys[keys.size() - 1][1] as Vector3).normalized()


static func envelope(t: float) -> float:
	return clampf(minf(t / RAMP_IN, (1.0 - t) / RAMP_OUT), 0.0, 1.0)


func _process_modification_with_delta(delta: float) -> void:
	if _kind == &"":
		return
	_elapsed += delta
	if _elapsed >= _duration:
		_kind = &""
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var t := _elapsed / _duration
	var weight := envelope(t)
	var swing := drive_at(t) if _kind == KICK else _torso_swing(t)
	var torso := (KICK_TORSO if _kind == KICK else PUNCH_TORSO) * weight * swing
	if _kind == KICK:
		_brace(skeleton, weight * swing)
	for bone_name: String in TORSO_BONES:
		var torso_bone := skeleton.find_bone(bone_name)
		if torso_bone >= 0:
			_rotate_bone(skeleton, torso_bone, Vector3(deg_to_rad(torso.x), deg_to_rad(torso.y), deg_to_rad(torso.z)) * 0.5)
	var tracks := _tracks(_kind)
	for bone_name: String in tracks:
		var bone := skeleton.find_bone(bone_name)
		var child := skeleton.find_bone(tracks[bone_name][0])
		var current := skeleton.get_bone_global_pose(child).origin - skeleton.get_bone_global_pose(bone).origin
		if current.length_squared() < 0.000001:
			continue
		var turn := Quaternion(current.normalized(), direction_at(_kind, bone_name, t))
		_rotate_bone_quaternion(skeleton, bone, Quaternion.IDENTITY.slerp(turn, weight))


## How far the kick's hips have driven in at time share `t` (0..1).
static func drive_at(t: float) -> float:
	for index in range(1, KICK_DRIVE.size()):
		var next: Array = KICK_DRIVE[index]
		if t <= float(next[0]):
			var previous: Array = KICK_DRIVE[index - 1]
			var k := (t - float(previous[0])) / (float(next[0]) - float(previous[0]))
			return lerpf(float(previous[1]), float(next[1]), k * k * (3.0 - 2.0 * k))
	return 0.0


# Pushes the hips in behind the kick and braces the standing leg so its foot stays put.
func _brace(skeleton: Skeleton3D, amount: float) -> void:
	var hips := skeleton.find_bone("Hips")
	var thigh := skeleton.find_bone("RightUpLeg")
	var foot := skeleton.find_bone("RightFoot")
	if hips >= 0 and thigh >= 0 and foot >= 0:
		var leg := skeleton.get_bone_global_rest(thigh).origin.distance_to(skeleton.get_bone_global_rest(foot).origin)
		var shift := KICK_HIPS_SHIFT * leg * amount
		var parent := skeleton.get_bone_parent(hips)
		if parent >= 0:
			shift = skeleton.get_bone_global_pose(parent).basis.inverse() * shift
		skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + shift)
	for bone_name: String in KICK_BRACE:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			_rotate_bone(skeleton, bone, Vector3(deg_to_rad(float(KICK_BRACE[bone_name]) * amount), 0.0, 0.0))


# 0 at the start, 1 once the foot or fist has landed, back to 0 on recovery.
func _torso_swing(t: float) -> float:
	return smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(0.7, 1.0, t))


static func _tracks(kind: StringName) -> Dictionary:
	match kind:
		KICK:
			return KICK_TRACKS
		PUNCH:
			return PUNCH_TRACKS
	return {}


func _rotate_bone(skeleton: Skeleton3D, bone: int, rotation_vector: Vector3) -> void:
	var angle := rotation_vector.length()
	if angle >= 0.00001:
		_rotate_bone_quaternion(skeleton, bone, Quaternion(rotation_vector / angle, angle))


# Turns a bone about its joint by a skeleton-space rotation (hit_reaction.gd).
func _rotate_bone_quaternion(skeleton: Skeleton3D, bone: int, turn: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := Quaternion.IDENTITY
	if parent >= 0:
		parent_rotation = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var local := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, (parent_rotation.inverse() * turn * parent_rotation * local).normalized())
