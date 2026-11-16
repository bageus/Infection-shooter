extends SkeletonModifier3D
## Moving on a diagonal the main clip is the nearer of the two straight cycles (forward, back, left, right); its
## feet would push along that axis and visibly slide sideways. This blends the legs toward the other axis's cycle,
## sampled at the same phase (the cycles of one gait share their length and footfalls), by how far the motion
## leans toward it: half at 45 degrees. The hips stay on the main clip, so the torso and the gun keep their aim.

const LEG_BONES := ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]

var player: AnimationPlayer
var clip: StringName = &""
var weight := 0.0
var _animation: Animation
var _tracks := {} # bone index -> rotation track


func _process_modification() -> void:
	if player == null or clip.is_empty() or weight <= 0.001 or not player.has_animation(clip) or not player.is_playing():
		return
	var main_length := player.current_animation_length
	if main_length <= 0.0:
		return
	var animation := player.get_animation(clip)
	if animation != _animation:
		_bind(animation)
	var time := fposmod(player.current_animation_position / main_length, 1.0) * animation.length
	var skeleton := get_skeleton()
	for bone: int in _tracks:
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(animation.rotation_track_interpolate(_tracks[bone], time), weight))


func _bind(animation: Animation) -> void:
	_animation = animation
	_tracks.clear()
	var skeleton := get_skeleton()
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := skeleton.find_bone(String(animation.track_get_path(track).get_concatenated_subnames()))
		if bone >= 0 and skeleton.get_bone_name(bone) in LEG_BONES:
			_tracks[bone] = track
