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
	for name: String in held:
		var held_bone := skeleton.find_bone(name)
		if held_bone >= 0:
			kept[held_bone] = skeleton.get_bone_global_pose(held_bone).basis.orthonormalized()
	var clip_time := fposmod(_time * speed, _animation.length)
	for bone: int in _tracks:
		var pose := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, pose.slerp(_animation.rotation_track_interpolate(_tracks[bone], clip_time), clampf(weight, 0.0, 1.0)))
	# Bone indices run parents first, so each held bone sees its parent's final pose.
	var order := kept.keys()
	order.sort()
	for bone: int in order:
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * (kept[bone] as Basis)).orthonormalized().get_rotation_quaternion())
