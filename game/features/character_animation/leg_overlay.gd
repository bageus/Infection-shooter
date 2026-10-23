extends SkeletonModifier3D
## Loops a locomotion clip on the leg bones only, over whatever the rest of the
## skeleton is playing: a running enemy keeps stepping while its attack clip
## swings the arms and torso. Presentation only.

const LEG_BONES := ["L_Thigh", "L_Shin", "L_Foot", "L_Toe", "R_Thigh", "R_Shin", "R_Foot", "R_Toe"]

var fade_seconds := 0.12
## Keeps stepping this long after the speed dips to zero for a tick.
var hold_seconds := 0.25

var _hold := 0.0

var _animation: Animation
var _time := 0.0
var _scale := 1.0
var _weight := 0.0
var _wanted := 0.0
var _tracks := {} # bone index -> rotation track


## The overlay on the first skeleton under `model`, or null without one.
static func attach(model: Node) -> SkeletonModifier3D:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var legs := new()
	legs.name = "AttackLegs"
	(skeletons[0] as Node).add_child(legs)
	return legs


## Keeps `animation` looping on the legs at `time_scale` until release().
func follow(animation: Animation, time_scale: float) -> void:
	if animation != _animation:
		_animation = animation
		_tracks.clear()
		var skeleton := get_skeleton()
		for track in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			var bone_name := String(animation.track_get_path(track).get_concatenated_subnames())
			if bone_name in LEG_BONES and skeleton.find_bone(bone_name) >= 0:
				_tracks[skeleton.find_bone(bone_name)] = track
	_scale = time_scale
	_wanted = 1.0


## Follows `animation` while the character moves (or moved within hold_seconds); null releases.
func drive(animation: Animation, time_scale: float, moving: bool) -> void:
	_hold = hold_seconds if moving else maxf(0.0, _hold - get_process_delta_time())
	if animation != null and _hold > 0.0:
		follow(animation, time_scale)
	else:
		release()


## Fades the legs back to whatever the main clip plays.
func release() -> void:
	_wanted = 0.0


## Drops the legs back to the main clip at once (the body is dead or ragdolled).
func stop() -> void:
	_wanted = 0.0
	_weight = 0.0


func is_following() -> bool:
	return _weight > 0.0 or _wanted > 0.0


func _process_modification() -> void:
	if _animation == null:
		return
	var delta := get_process_delta_time()
	_weight = move_toward(_weight, _wanted, delta / fade_seconds)
	if _weight <= 0.0:
		return
	_time = fposmod(_time + delta * _scale, _animation.length)
	var skeleton := get_skeleton()
	for bone: int in _tracks:
		var pose := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, pose.slerp(_animation.rotation_track_interpolate(_tracks[bone], _time), _weight))
