extends SkeletonModifier3D
## Plays a clip on some bones only, faded in and out over whatever the rest of
## the skeleton is doing (ADR-0045): a hit flinch of the upper body while the
## legs keep running. Presentation only.

const UPPER_BODY := ["Spine", "Chest", "Neck", "Head", "L_Shoulder", "L_UpperArm", "L_Forearm", "L_Hand", "R_Shoulder", "R_UpperArm", "R_Forearm", "R_Hand"]

var bones: Array = UPPER_BODY
## Bones that keep their skeleton-space orientation while the clip plays over their parents (the arms keep the weapon grip).
var held: Array = []
var fade_in := 0.08
var fade_out := 0.3
## Playback rate of the clip; `length` and the fades are in real seconds.
var speed := 1.0
## Clip seconds over which the end of a pass is blended into its start while the clip loops (0: a plain loop).
var loop_blend := 0.0

var _animation: Animation
var _length := 0.0
var _time := 0.0
var _tracks := {} # bone index -> rotation track


## Starts `animation`; its rotation tracks named after `bones` are blended in. `length` > 0 ends it sooner (the clip loops).
func play(animation: Animation, length := 0.0) -> void:
	_animation = animation
	_length = length if length > 0.0 else animation.length
	_time = 0.0
	_tracks.clear()
	var skeleton := get_skeleton()
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone_name := String(animation.track_get_path(track).get_concatenated_subnames())
		if bone_name in bones and skeleton.find_bone(bone_name) >= 0:
			_tracks[skeleton.find_bone(bone_name)] = track


func is_playing() -> bool:
	return _animation != null


## Stops at once (the body died or was ragdolled).
func stop() -> void:
	_animation = null


## Keeps a running clip from ending: it fades out only once nobody asks for it any more.
func hold() -> void:
	_length = maxf(_length, _time + fade_out + 0.05)


## Seconds still to play.
func remaining() -> float:
	return maxf(_length - _time, 0.0) if _animation != null else 0.0


func _process_modification() -> void:
	if _animation == null:
		return
	var delta := get_process_delta_time()
	_time += delta
	if _time >= _length:
		_animation = null
		return
	var weight := minf(_time / fade_in, minf((_length - _time) / fade_out, 1.0))
	var skeleton := get_skeleton()
	var kept := {}
	for held_name: String in held:
		var held_bone := skeleton.find_bone(held_name)
		if held_bone >= 0:
			kept[held_bone] = skeleton.get_bone_global_pose(held_bone).basis.orthonormalized()
	var clip_time := fposmod(_time * speed, _animation.length)
	# A blended loop: after the first pass the clip repeats from loop_blend on, and the end of each pass fades into that start.
	var span := _animation.length - loop_blend
	var pass_time := _time * speed
	var into := 0.0
	if loop_blend > 0.0:
		clip_time = fposmod(pass_time, span) + (loop_blend if pass_time >= span else 0.0)
		into = clampf((fposmod(pass_time, span) - (span - loop_blend)) / loop_blend, 0.0, 1.0)
	for bone: int in _tracks:
		var pose := skeleton.get_bone_pose_rotation(bone)
		var target: Quaternion = _animation.rotation_track_interpolate(_tracks[bone], clip_time)
		if into > 0.0:
			var start: Quaternion = _animation.rotation_track_interpolate(_tracks[bone], loop_blend - (span - fposmod(pass_time, span)))
			target = target.slerp(start, into)
		skeleton.set_bone_pose_rotation(bone, pose.slerp(target, clampf(weight, 0.0, 1.0)))
	# Bone indices run parents first, so each held bone sees its parent's final pose.
	var order := kept.keys()
	order.sort()
	for bone: int in order:
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * (kept[bone] as Basis)).orthonormalized().get_rotation_quaternion())
