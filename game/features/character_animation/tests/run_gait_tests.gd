extends SceneTree
## Runtime checks for the procedural leg gait (ADR-0016): the authored player
## walk clips step with one leg only; the gait must alternate both legs at the
## character's real speed and hand the legs back to the clip when standing.
## In every direction of travel each knee bends toward where its foot points.

const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")

var failures := 0
var _samples: Array[Vector3] = []
var _knee_errors: Array[float] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var character := CharacterBody3D.new()
	root.add_child(character)
	var body := MODEL.instantiate() as Node3D
	body.name = "Body"
	character.add_child(body)
	var driver := DRIVER.new()
	driver.name = "AnimationDriver"
	driver.procedural_gait = true
	driver.configure_clip_selector(func() -> StringName: return &"Walk_Pistol_OneHand_Forward" if character.velocity.length() > 0.15 else &"Idle_Pistol_OneHand")
	character.add_child(driver)
	await process_frame
	var gait: SkeletonModifier3D = driver.gait
	_expect(gait != null, "The driver attaches the gait to the player skeleton.")
	if gait == null:
		_finish()
		return
	var skeleton := gait.get_skeleton()
	var left := skeleton.find_bone("LeftFoot")
	var right := skeleton.find_bone("RightFoot")
	# Poses are read right after the modifiers ran for the frame.
	skeleton.skeleton_updated.connect(func() -> void: _samples.append(skeleton.get_bone_global_pose(left).origin - skeleton.get_bone_global_pose(right).origin))
	skeleton.skeleton_updated.connect(func() -> void: _record_knees(skeleton))
	character.velocity = Vector3(0, 0, 6.0)
	await create_timer(0.5).timeout
	_samples.clear()
	await create_timer(1.5).timeout
	var leads: Array[float] = []
	for sample in _samples:
		leads.append(sample.z)
	var most: float = leads.max()
	var least: float = leads.min()
	_expect(most > 0.25 and least < -0.25, "Both legs take full steps in turn (%.2f / %.2f)." % [most, least])
	var swaps := 0
	for i in range(1, leads.size()):
		if signf(leads[i]) != signf(leads[i - 1]):
			swaps += 1
	_expect(swaps >= 4, "The legs keep alternating (%d swaps in 1.5 s)." % swaps)
	var width := 0.0
	for sample in _samples:
		width = maxf(width, absf(sample.x))
	# The rest pose stands with the ankles 0.47 m apart; a natural gait steps close to the midline.
	_expect(width < 0.3, "The feet step under the hips, not straddling (%.2f m apart)." % width)
	_expect(gait.get("weight") > 0.95, "The gait owns the legs while moving.")
	character.velocity = Vector3.ZERO
	await create_timer(0.6).timeout
	_expect(float(gait.get("weight")) < 0.01, "Standing hands the legs back to the authored idle.")
	character.velocity = Vector3(6.0, 0, 0)
	await create_timer(0.5).timeout
	_samples.clear()
	await create_timer(0.8).timeout
	var fore_aft := 0.0
	for sample in _samples:
		fore_aft = maxf(fore_aft, absf(sample.z))
	_expect(fore_aft > 0.15, "Strafing turns the legs into diagonal steps (%.2f m fore-aft)." % fore_aft)
	for heading in [Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(0, 0, -1), Vector3(-1, 0, 0)]:
		character.velocity = heading.normalized() * 5.0
		await create_timer(0.4).timeout
		_knee_errors.clear()
		await create_timer(1.0).timeout
		var worst: float = _knee_errors.max() if not _knee_errors.is_empty() else 180.0
		_expect(worst < 25.0, "Walking toward %s, the knees bend the way the feet point (worst %.0f degrees)." % [heading, worst])
	_finish()


# Angle between where a bent knee sticks out of the hip-ankle line and where
# its foot points, seen from above; nearly straight legs are skipped.
func _record_knees(skeleton: Skeleton3D) -> void:
	for side in ["Left", "Right"]:
		var hip := skeleton.get_bone_global_pose(skeleton.find_bone(side + "UpLeg")).origin
		var knee := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Leg")).origin
		var ankle := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Foot")).origin
		var toe := skeleton.get_bone_global_pose(skeleton.find_bone(side + "ToeBase")).origin
		var axis := (ankle - hip).normalized()
		var out := (knee - hip) - axis * (knee - hip).dot(axis)
		if out.length() < 0.3 * (knee - hip).length():
			continue
		out.y = 0.0
		var foot := toe - ankle
		foot.y = 0.0
		_knee_errors.append(rad_to_deg(absf(out.signed_angle_to(foot, Vector3.UP))))


func _finish() -> void:
	print("Gait tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
