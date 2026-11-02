extends SkeletonModifier3D
## Procedural melee strike layered over the playing clip (ADR-0066): a front
## kick with the rear (left) leg or a jab with the left arm. Each limb bone is
## aimed along keyframed skeleton-space directions and blended in and out, so
## everything else keeps its clip. The kick is baked from the "Standing Melee
## Attack Kick" motion capture, mirrored because the hero stands with the right
## foot forward (kick_clip_data.gd): the rear leg swings through, the hips turn
## and travel behind it, the standing leg and torso follow the capture, and the
## arms keep their pose. Front is +Z, up +Y. Presentation only.

const KICK_DATA := preload("res://game/features/character_animation/kick_clip_data.gd")

const KICK := &"kick"
const PUNCH := &"punch"
const KICK_SECONDS := 0.6
const PUNCH_SECONDS := 0.4
## Seconds from the start to the moment the foot or fist lands.
const KICK_IMPACT := 0.27
const PUNCH_IMPACT := 0.14

# Limb tracks: bone -> [child bone (gives the bone's direction), keys]; a key is
# [time share, skeleton-space direction the bone points along]. The kick's come from kick_clip_data.gd.
const KICK_TRACKS := KICK_DATA.KICK_LEG
## Bones that keep their skeleton-space orientation through a kick (the arms hold their pose).
const KICK_HELD := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const PUNCH_TRACKS := {
	"LeftArm": ["LeftForeArm", [[0.0, Vector3(0.6, -0.8, 0.3)], [0.3, Vector3(0.6, -0.4, -0.6)], [0.5, Vector3(0.12, 0.05, 1.0)], [0.65, Vector3(0.12, 0.05, 1.0)], [1.0, Vector3(0.6, -0.8, 0.3)]]],
	"LeftForeArm": ["LeftWrist", [[0.0, Vector3(0.3, -0.5, 0.8)], [0.3, Vector3(0.2, 0.3, 0.9)], [0.5, Vector3(0.1, 0.05, 1.0)], [0.65, Vector3(0.1, 0.05, 1.0)], [1.0, Vector3(0.3, -0.5, 0.8)]]],
}
# Torso lean/twist (degrees about skeleton axes) at the strike moment, scaled by the envelope.
const PUNCH_TORSO := Vector3(-3.0, -14.0, 0.0)
const TORSO_BONES := ["Spine1", "Spine2"]
## Share of the blend that is in full effect: ramps in over the first 15 % and out over the last 25 %.
const RAMP_IN := 0.15
const RAMP_OUT := 0.25

## Kicking foot's skeleton-space position after the last kick update (read back by tests).
var kick_foot := Vector3.ZERO
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
			if keys.size() < 8:
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
	if _kind == KICK:
		_kick(skeleton, t, weight)
		return
	var torso := PUNCH_TORSO * weight * _torso_swing(t)
	for bone_name: String in TORSO_BONES:
		var torso_bone := skeleton.find_bone(bone_name)
		if torso_bone >= 0:
			_rotate_bone(skeleton, torso_bone, Vector3(deg_to_rad(torso.x), deg_to_rad(torso.y), deg_to_rad(torso.z)) * 0.5)
	_aim_tracks(skeleton, PUNCH_TRACKS, t, weight)


## Value of the baked key list `keys` ([[share, Vector3], ...]) at time share `t`.
static func sample(keys: Array, t: float) -> Vector3:
	for index in range(1, keys.size()):
		var next: Array = keys[index]
		if t <= float(next[0]):
			var previous: Array = keys[index - 1]
			var span := float(next[0]) - float(previous[0])
			return (previous[1] as Vector3).lerp(next[1], 0.0 if span <= 0.0 else (t - float(previous[0])) / span)
	return keys[keys.size() - 1][1]


# The kick from the mirrored capture: the standing leg and arms are noted first, then the hips travel and
# the torso turns, the standing leg turns by the capture's amount from where it was, the arms are put back
# to their own orientation, and the kicking leg is aimed along its baked directions.
func _kick(skeleton: Skeleton3D, t: float, weight: float) -> void:
	var stand := {}
	for bone_name: String in KICK_DATA.STAND_LEG:
		var bone := skeleton.find_bone(bone_name)
		var child := skeleton.find_bone(KICK_DATA.STAND_LEG[bone_name][0])
		stand[bone_name] = (skeleton.get_bone_global_pose(child).origin - skeleton.get_bone_global_pose(bone).origin).normalized()
	var held := {}
	for bone_name: String in KICK_HELD:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			held[bone] = skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	_shift_hips(skeleton, sample(KICK_DATA.KICK_HIPS, t) * weight)
	for bone_name: String in KICK_DATA.KICK_TORSO_TURNS:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			_rotate_bone(skeleton, bone, sample(KICK_DATA.KICK_TORSO_TURNS[bone_name], t) * weight)
	for bone_name: String in KICK_DATA.STAND_LEG:
		var turn := sample(KICK_DATA.STAND_LEG[bone_name][1], t) * weight
		var angle := turn.length()
		if angle > 0.00001:
			var direction: Vector3 = stand[bone_name]
			var target := Quaternion(turn / angle, angle) * direction
			var bone := skeleton.find_bone(bone_name)
			var child := skeleton.find_bone(KICK_DATA.STAND_LEG[bone_name][0])
			var current := skeleton.get_bone_global_pose(child).origin - skeleton.get_bone_global_pose(bone).origin
			_rotate_bone_quaternion(skeleton, bone, Quaternion(current.normalized(), target))
	for bone: int in held:
		var parent := skeleton.get_bone_parent(bone)
		var parent_rotation := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
		skeleton.set_bone_pose_rotation(bone, (parent_rotation.inverse() * (held[bone] as Quaternion)).normalized())
	_aim_tracks(skeleton, KICK_TRACKS, t, weight)
	kick_foot = skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin


# Aims every track bone towards its keyed direction, by `weight`.
func _aim_tracks(skeleton: Skeleton3D, tracks: Dictionary, t: float, weight: float) -> void:
	for bone_name: String in tracks:
		var bone := skeleton.find_bone(bone_name)
		var child := skeleton.find_bone(tracks[bone_name][0])
		var current := skeleton.get_bone_global_pose(child).origin - skeleton.get_bone_global_pose(bone).origin
		if current.length_squared() < 0.000001:
			continue
		var turn := Quaternion(current.normalized(), direction_at(_kind, bone_name, t))
		_rotate_bone_quaternion(skeleton, bone, Quaternion.IDENTITY.slerp(turn, weight))


# Moves the hips by `share` of the leg length (skeleton space).
func _shift_hips(skeleton: Skeleton3D, share: Vector3) -> void:
	var hips := skeleton.find_bone("Hips")
	var thigh := skeleton.find_bone("LeftUpLeg")
	var foot := skeleton.find_bone("LeftFoot")
	if hips < 0 or thigh < 0 or foot < 0:
		return
	var leg := skeleton.get_bone_global_rest(thigh).origin.distance_to(skeleton.get_bone_global_rest(foot).origin)
	var shift := share * leg
	var parent := skeleton.get_bone_parent(hips)
	if parent >= 0:
		shift = skeleton.get_bone_global_pose(parent).basis.inverse() * shift
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + shift)


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
