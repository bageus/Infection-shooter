extends RefCounted
## Poses a far character's skeleton every `step`-th frame with the time of all of them, so the renderer and the
## bone-attached hit shapes update `step` times less often. Step 1 is every frame.
var step := 1
var _time := 0.0
var _skeletons: Array[Skeleton3D] = []


func set_step(mixer: AnimationPlayer, value: int) -> void:
	value = maxi(value, 1)
	if value == step or mixer == null:
		return
	step = value
	if _skeletons.is_empty():
		for found in mixer.get_parent().find_children("*", "Skeleton3D", true, false):
			_skeletons.append(found as Skeleton3D)
	var manual := value > 1
	mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if manual else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	for skeleton in _skeletons:
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL if manual else Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	_time = 0.0


func advance(mixer: AnimationPlayer, delta: float, offset: int) -> void:
	_time += delta
	if (Engine.get_process_frames() + offset) % step != 0:
		return
	mixer.advance(_time)
	for skeleton in _skeletons:
		skeleton.advance(_time)
	_time = 0.0
