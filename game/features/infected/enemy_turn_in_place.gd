extends RefCounted
## Unaware enemy that wants to walk off the other way turns on the spot with a baked turn clip
## (TurnLeft / TurnRight, optional numbered variants) instead of spinning (ADR-0045, ADR-0070).
## The clip's yaw_curve meta says how much of the turn is done at each frame.

const PERCEPTION := preload("res://game/features/infected/enemy_perception.gd")
const MIN_ANGLE := 1.3 # rad, about 75 degrees
const SPEED := 1.25 # playback rate of the turn clip

var _time := -1.0
var _length := 1.0
var _from := 0.0
var _angle := 0.0
var _clip := &""
var _curve := PackedFloat32Array()


func active() -> bool:
	return _time >= 0.0


## Starts a turn from `yaw_before` toward the face direction; false when it is not worth one or no clip fits.
func start(animation: Node, yaw_before: float, face: Vector3) -> bool:
	if animation == null or face.length_squared() < 0.0001:
		return false
	var angle := wrapf(atan2(-face.x, -face.z) - yaw_before, -PI, PI)
	if absf(angle) < MIN_ANGLE:
		return false
	var base := "TurnLeft" if angle > 0.0 else "TurnRight"
	var names: Array[StringName] = []
	for candidate: String in [base, base + "2"]:
		if float(animation.call("clip_length", StringName(candidate))) > 0.0:
			names.append(StringName(candidate))
	if names.is_empty():
		return false
	var clip: StringName = names[randi() % names.size()]
	var curve: PackedFloat32Array = animation.call("clip_meta", clip, &"yaw_curve", PackedFloat32Array())
	if curve.size() < 2 or absf(float(animation.call("clip_meta", clip, &"turn_yaw", 0.0))) < 0.1:
		return false
	var length := float(animation.call("play_named_one_shot", clip, 0.12, SPEED))
	if length <= 0.0:
		return false
	_clip = clip
	_curve = curve
	_length = length
	_from = yaw_before
	_angle = angle
	_time = 0.0
	return true


## Advances the turn and returns the yaw the body should have now.
func step(delta: float) -> float:
	_time += delta
	var done := _time >= _length
	var frame := clampf(_time * SPEED * 30.0, 0.0, float(_curve.size() - 1))
	var low := int(floor(frame))
	var high := mini(low + 1, _curve.size() - 1)
	var progress := lerpf(_curve[low], _curve[high], frame - floor(frame)) / _curve[_curve.size() - 1]
	if done:
		_time = -1.0
	return _from + _angle * (1.0 if done else clampf(progress, 0.0, 1.0))


## The chase began: the clip is dropped and the body keeps its yaw.
func cancel(animation: Node) -> void:
	if _time >= 0.0 and animation != null:
		animation.call("cancel_one_shot", _clip)
	_time = -1.0


## One physics tick of a turn under way; true while the body is held for it.
func drive(actor: CharacterBody3D, delta: float) -> bool:
	if _time < 0.0:
		return false
	actor.rotation.y = step(delta)
	actor.velocity.x = 0.0
	actor.velocity.z = 0.0
	actor.call("_apply_gravity", delta)
	actor.move_and_slide()
	return true


## One unaware tick: finishes a turn under way, else lets the enemy look and stroll, and a standing
## one that now wants the other way starts a turn on the spot.
func tick(actor: CharacterBody3D, animation: Node, delta: float) -> void:
	if drive(actor, delta):
		return
	var yaw_before := actor.rotation.y
	var standing := Vector2(actor.velocity.x, actor.velocity.z).length() < 0.3
	var senses: RefCounted = actor.get("_senses")
	senses.call("step_unaware", actor, delta)
	if standing and not senses.call("is_chasing") and senses.get("state") in [PERCEPTION.State.UNAWARE, PERCEPTION.State.RETURN] and start(animation, yaw_before, actor.get("_face_direction")):
		actor.rotation.y = yaw_before
		actor.velocity = Vector3(0.0, actor.velocity.y, 0.0)
