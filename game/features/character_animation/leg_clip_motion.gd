extends SkeletonModifier3D
## Authored hips-and-legs clips layered over the upper-body clips (ADR-0044).
##
## Running plays the eight Mixamo run clips retargeted to the skeleton
## (tools/build_player_leg_clips.gd), blended by the direction of travel
## relative to the body, so the legs follow the movement while the arms, the
## shoulders and the weapon grip keep the authored upper-body pose: the spine
## is counter-turned by whatever the hips clip rotates. A dodge plays one
## whole-hips clip (roll or strafe jump) instead and lets the torso ride along.
## Presentation only: reads the character's velocity, never changes it.

## Emitted when a foot lands (side 0 = left, 1 = right) while the clips own the legs.
signal stepped(side: int, speed: float)

const RING := ["Run_Forward", "Run_Forward_Left", "Run_Left", "Run_Backward_Left", "Run_Backward", "Run_Backward_Right", "Run_Right", "Run_Forward_Right"]
const LEG_BONES := ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
const SPINE_NAMES := ["Spine", "mixamorig:Spine"]
const HIPS_NAMES := ["Hips", "mixamorig:Hips"]
## Body turn rate (rad/s) where on-the-spot stepping starts and where it is full.
const TURN_RATE_MIN := 0.8
const TURN_RATE_FULL := 2.5
## Share of the run cycle's amplitude used when turning: small shuffling steps, not jogging.
const TURN_STEP_WEIGHT := 0.3
const TURN_TIME_SCALE := 0.8
const DODGE_BLEND_IN := 0.06
const DODGE_BLEND_OUT := 0.12
## Bones kept at or above their rest height (skeleton space): the rest pose stands on the floor.
const GROUND_BONES := ["LeftFoot", "LeftToeBase", "RightFoot", "RightToeBase"]

var character: CharacterBody3D
var clips: AnimationLibrary
## Modifier nodes (siblings on the skeleton) that fight a tumbling body and sleep during a dodge.
var suspend_during_dodge: Array[StringName] = [&"BodyAim", &"EquipmentPose"]
var weight := 0.0
var phase := 0.0
var travel_angle := 0.0 # radians, 0 forward, + toward the body's left
## Playback speed follows speed / the clip's planted-foot speed within these bounds (2.6 lets the 8.1 m/s sprint keep its feet planted).
var min_time_scale := 0.5
var max_time_scale := 2.6
var playback_multiplier := 1.0

var _last_yaw := 0.0
var _has_yaw := false
var _hips := -1
var _spine := -1
var _bones: Array[int] = [] # LEG_BONES order
var _ground: Array[Vector2] = [] # GROUND_BONES: (bone, rest height)
var _ready_bones := false
var _data: Dictionary = {} # clip name -> sampled frames
var _dodge := ""
var _dodge_time := 0.0
var _dodge_duration := 0.0
var _dodge_yaw := 0.0
var _suspended: Array[Node] = []


## Starts a dodge clip for `duration` seconds, turning the body by `yaw` radians
## (about the skeleton's up axis) so the clip's travel points where the dodge goes.
func start_dodge(clip_name: String, duration: float, yaw: float) -> bool:
	if clips == null or not clips.has_animation(clip_name):
		return false
	_dodge = clip_name
	_dodge_time = 0.0
	_dodge_duration = maxf(duration, 0.05)
	_dodge_yaw = yaw
	_set_suspended(true)
	return true


func is_dodging() -> bool:
	return not _dodge.is_empty()


func cancel_dodge() -> void:
	_dodge = ""
	_set_suspended(false)


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or character == null or clips == null:
		return
	if not _ready_bones:
		_ready_bones = _resolve(skeleton)
		if not _ready_bones:
			return
	if not _dodge.is_empty():
		_apply_dodge(skeleton, delta)
		return
	_apply_run(skeleton, delta)


func _apply_run(skeleton: Skeleton3D, delta: float) -> void:
	var to_skeleton := skeleton.global_basis.inverse()
	var velocity := to_skeleton * Vector3(character.velocity.x, 0.0, character.velocity.z)
	var speed := Vector2(velocity.x, velocity.z).length()
	# Turning on the spot steps the feet (the forward cycle, slowed) instead of spinning rigidly.
	var yaw := skeleton.global_rotation.y
	var turn_rate := absf(angle_difference(_last_yaw, yaw)) / maxf(delta, 0.0001) if _has_yaw else 0.0
	_last_yaw = yaw
	_has_yaw = true
	var turning := smoothstep(TURN_RATE_MIN, TURN_RATE_FULL, turn_rate) if speed <= 0.15 else 0.0
	weight = move_toward(weight, maxf(smoothstep(0.15, 0.9, speed), turning * TURN_STEP_WEIGHT), delta * 6.0)
	if weight <= 0.001:
		return
	if speed <= 0.15:
		travel_angle = wrapf(travel_angle + angle_difference(travel_angle, 0.0) * (1.0 - exp(-14.0 * delta)), -PI, PI)
	else:
		var wanted := atan2(velocity.x, velocity.z)
		travel_angle = wrapf(travel_angle + angle_difference(travel_angle, wanted) * (1.0 - exp(-14.0 * delta)), -PI, PI)
	var sector := (travel_angle + TAU) / (PI * 0.25)
	var first := int(floor(sector)) % 8
	var mix := sector - floorf(sector)
	var from_data := _clip(RING[first])
	var to_data := _clip(RING[(first + 1) % 8])
	var reference := lerpf(from_data.ref_speed, to_data.ref_speed, mix)
	var time_scale := (TURN_TIME_SCALE if speed <= 0.15 else clampf(speed / maxf(reference, 0.1), min_time_scale, max_time_scale)) * playback_multiplier
	var previous := phase
	var cycle := lerpf(from_data.length, to_data.length, mix)
	phase = fposmod(phase + delta * time_scale / cycle, 1.0)
	var near_data: Dictionary = from_data if mix < 0.5 else to_data
	if weight > 0.5:
		for side in 2:
			if _crossed(previous, phase, float(near_data.plant[side])):
				stepped.emit(side, speed)
	var hips_before := skeleton.get_bone_pose_rotation(_hips)
	var hips_rotation := _sample_rotation(from_data, 0, phase).slerp(_sample_rotation(to_data, 0, phase), mix)
	var hips_position := _sample_position(from_data, phase).lerp(_sample_position(to_data, phase), mix)
	var hips_pose := hips_before.slerp(hips_rotation, weight)
	skeleton.set_bone_pose_rotation(_hips, hips_pose)
	skeleton.set_bone_pose_position(_hips, skeleton.get_bone_pose_position(_hips).lerp(hips_position, weight))
	_counter_turn_spine(skeleton, hips_before, hips_pose)
	for index in LEG_BONES.size():
		var target := _sample_rotation(from_data, index + 1, phase).slerp(_sample_rotation(to_data, index + 1, phase), mix)
		var bone: int = _bones[index]
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(target, weight))
	_keep_feet_above_floor(skeleton)


# Retargeted run clips put the planted foot a few centimetres under the floor; lift the hips until it is on it.
func _keep_feet_above_floor(skeleton: Skeleton3D) -> void:
	var lift := 0.0
	for entry in _ground:
		lift = maxf(lift, entry.y - skeleton.get_bone_global_pose(int(entry.x)).origin.y)
	if lift <= 0.0:
		return
	var parent := skeleton.get_bone_parent(_hips)
	var up := Vector3(0.0, lift, 0.0) if parent < 0 else skeleton.get_bone_global_pose(parent).basis.inverse() * Vector3(0.0, lift, 0.0)
	skeleton.set_bone_pose_position(_hips, skeleton.get_bone_pose_position(_hips) + up)


func _apply_dodge(skeleton: Skeleton3D, delta: float) -> void:
	_dodge_time += delta
	if _dodge_time >= _dodge_duration + DODGE_BLEND_OUT:
		cancel_dodge()
		return
	var data := _clip(_dodge)
	var blend := minf(_dodge_time / DODGE_BLEND_IN, (_dodge_duration + DODGE_BLEND_OUT - _dodge_time) / DODGE_BLEND_OUT)
	blend = clampf(blend, 0.0, 1.0)
	weight = blend
	# The whole clip plays over the dodge, however long the source clip is.
	var u := clampf(_dodge_time / _dodge_duration, 0.0, 1.0)
	var yaw := Quaternion(Vector3.UP, _dodge_yaw)
	var hips_rotation := yaw * _sample_rotation(data, 0, u, false)
	var hips_position := _sample_position(data, u, false)
	skeleton.set_bone_pose_rotation(_hips, skeleton.get_bone_pose_rotation(_hips).slerp(hips_rotation, blend))
	skeleton.set_bone_pose_position(_hips, skeleton.get_bone_pose_position(_hips).lerp(hips_position, blend))
	for index in LEG_BONES.size():
		var bone: int = _bones[index]
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(_sample_rotation(data, index + 1, u, false), blend))


# The spine keeps the world orientation its authored pose had before the hips
# were replaced, so the arms and the weapon do not follow the hips clip.
func _counter_turn_spine(skeleton: Skeleton3D, hips_before: Quaternion, hips_after: Quaternion) -> void:
	if _spine < 0:
		return
	var spine := skeleton.get_bone_pose_rotation(_spine)
	skeleton.set_bone_pose_rotation(_spine, hips_after.inverse() * hips_before * spine)


func _set_suspended(asleep: bool) -> void:
	if asleep:
		_suspended.clear()
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		for node_name in suspend_during_dodge:
			var node := skeleton.get_node_or_null(NodePath(node_name)) as SkeletonModifier3D
			if node != null and node.active:
				node.active = false
				_suspended.append(node)
		return
	for node in _suspended:
		if is_instance_valid(node):
			(node as SkeletonModifier3D).active = true
	_suspended.clear()


func _exit_tree() -> void:
	_set_suspended(false)


# Frames per track: [hips rotation, leg rotations...] plus hips positions.
func _clip(clip_name: String) -> Dictionary:
	if _data.has(clip_name):
		return _data[clip_name]
	var animation := clips.get_animation(clip_name)
	var rotations: Array = []
	var names: Array[String] = ["Hips"]
	names.append_array(LEG_BONES)
	for bone_name in names:
		var track := animation.find_track(NodePath("Skeleton3D:" + bone_name), Animation.TYPE_ROTATION_3D)
		var frames: Array[Quaternion] = []
		for key in animation.track_get_key_count(track):
			frames.append(animation.track_get_key_value(track, key))
		rotations.append(frames)
	var positions: Array[Vector3] = []
	var position_track := animation.find_track(NodePath("Skeleton3D:Hips"), Animation.TYPE_POSITION_3D)
	for key in animation.track_get_key_count(position_track):
		positions.append(animation.track_get_key_value(position_track, key))
	var data := {
		"length": animation.length,
		"rotations": rotations,
		"positions": positions,
		"ref_speed": float(animation.get_meta("ref_speed", 3.0)),
		"plant": [float(animation.get_meta("plant_left", 0.0)), float(animation.get_meta("plant_right", 0.5))],
	}
	_data[clip_name] = data
	return data


func _sample_rotation(data: Dictionary, track: int, u: float, loop := true) -> Quaternion:
	var frames: Array = data.rotations[track]
	var pair := _frame_pair(frames.size(), u, loop)
	if pair.x < 0:
		return Quaternion.IDENTITY
	return (frames[int(pair.x)] as Quaternion).slerp(frames[int(pair.y)] as Quaternion, pair.z)


func _sample_position(data: Dictionary, u: float, loop := true) -> Vector3:
	var frames: Array = data.positions
	var pair := _frame_pair(frames.size(), u, loop)
	if pair.x < 0:
		return Vector3.ZERO
	return (frames[int(pair.x)] as Vector3).lerp(frames[int(pair.y)] as Vector3, pair.z)


# Neighbouring frame indices and the blend between them (x, y = indices, z = t);
# x is -1 without frames. A loop wraps from the last frame to the first.
func _frame_pair(count: int, u: float, loop: bool) -> Vector3:
	if count == 0:
		return Vector3(-1, 0, 0)
	var offset := u * float(count) if loop else u * float(count - 1)
	var index := int(floor(offset))
	var next := index + 1
	if loop:
		index = posmod(index, count)
		next = posmod(next, count)
	else:
		index = clampi(index, 0, count - 1)
		next = clampi(next, 0, count - 1)
	return Vector3(index, next, offset - floorf(offset))


static func _crossed(before: float, after: float, mark: float) -> bool:
	if after >= before:
		return before < mark and after >= mark
	return before < mark or after >= mark


func _resolve(skeleton: Skeleton3D) -> bool:
	_hips = _first_bone(skeleton, HIPS_NAMES)
	_spine = _first_bone(skeleton, SPINE_NAMES)
	_bones.clear()
	for bone_name: String in LEG_BONES:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			return false
		_bones.append(index)
	_ground.clear()
	for bone_name: String in GROUND_BONES:
		var bone := skeleton.find_bone(bone_name)
		_ground.append(Vector2(bone, skeleton.get_bone_global_rest(bone).origin.y))
	for clip_name: String in RING:
		if not clips.has_animation(clip_name):
			return false
	return _hips >= 0


func _first_bone(skeleton: Skeleton3D, names: Array) -> int:
	for bone_name: String in names:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			return index
	return -1
