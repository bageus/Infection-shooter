extends SkeletonModifier3D
## Plays a clip on some bones only, faded in and out over whatever the rest of
## the skeleton is doing (ADR-0045): a hit flinch of the upper body while the
## legs keep running. Presentation only.

const UPPER_BODY := ["Spine", "Chest", "Neck", "Head", "L_Shoulder", "L_UpperArm", "L_Forearm", "L_Hand", "R_Shoulder", "R_UpperArm", "R_Forearm", "R_Hand"]

var bones: Array = UPPER_BODY
var fade_in := 0.08
var fade_out := 0.3

var _animation: Animation
var _time := 0.0
var _tracks := {} # bone index -> rotation track


## Starts `animation`; its rotation tracks named after `bones` are blended in.
func play(animation: Animation) -> void:
	_animation = animation
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


func _process_modification() -> void:
	if _animation == null:
		return
	var delta := get_process_delta_time()
	_time += delta
	if _time >= _animation.length:
		_animation = null
		return
	var weight := minf(_time / fade_in, minf((_animation.length - _time) / fade_out, 1.0))
	var skeleton := get_skeleton()
	for bone: int in _tracks:
		var pose := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, pose.slerp(_animation.rotation_track_interpolate(_tracks[bone], _time), clampf(weight, 0.0, 1.0)))
