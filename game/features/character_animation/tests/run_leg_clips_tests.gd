extends SceneTree
## Hips-and-legs clips (ADR-0044): legs follow the direction of travel, the
## upper body keeps its authored pose, the dodge plays a roll or a strafe jump.

const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")
const CLIPS := preload("res://models/objects/characters/player_legs/player_leg_clips.res")
const CLIP := &"Walk_Pistol_TwoHand_Forward"

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _make(clips: bool) -> CharacterBody3D:
	var character := CharacterBody3D.new()
	root.add_child(character)
	var body := MODEL.instantiate() as Node3D
	body.name = "Body"
	character.add_child(body)
	var driver := DRIVER.new()
	driver.name = "AnimationDriver"
	if clips:
		driver.leg_clips = CLIPS
	driver.configure_clip_selector(func() -> StringName: return CLIP if character.velocity.length() > 0.15 else &"Idle_Pistol_TwoHand")
	character.add_child(driver)
	return character


func _run() -> void:
	for name in ["Run_Forward", "Run_Forward_Right", "Dodge_Roll", "Dodge_Strafe_Left", "Dodge_Strafe_Right"]:
		_expect(CLIPS.has_animation(name), "Baked clip %s exists." % name)
	var character := _make(true)
	var plain := _make(false)
	plain.position.x = 3.0
	await process_frame
	var driver := character.get_node("AnimationDriver")
	var legs: SkeletonModifier3D = driver.legs
	_expect(legs != null, "Leg clips attach to the skeleton.")
	if legs == null:
		quit(1)
		return
	var skeleton := legs.get_skeleton()
	var reference := (plain.get_node("Body").find_children("*", "Skeleton3D", true, false)[0]) as Skeleton3D
	var steps := [0]
	driver.footstep.connect(func(_side: int, _speed: float) -> void: steps[0] += 1)
	var poses := {}
	for pair in [[skeleton, "legs"], [reference, "plain"]]:
		var watched: Skeleton3D = pair[0]
		var key: String = pair[1]
		watched.skeleton_updated.connect(func() -> void:
			for bone in ["LeftArm", "RightForeArm", "RightHand", "Spine2"]:
				poses[key + bone] = watched.get_bone_global_pose(watched.find_bone(bone)).basis)
	character.velocity = Vector3(0, 0, 5.0)
	plain.velocity = character.velocity
	await create_timer(1.2).timeout
	_expect(float(legs.weight) > 0.95, "The clips own the legs while running.")
	_expect(absf(float(legs.travel_angle)) < 0.1, "Forward travel plays the forward run.")
	_expect(steps[0] >= 4, "Feet land and report footsteps (%d)." % steps[0])
	for bone in ["LeftArm", "RightForeArm", "RightHand", "Spine2"]:
		var a: Basis = poses["legs" + bone]
		var b: Basis = poses["plain" + bone]
		_expect(a.get_rotation_quaternion().angle_to(b.get_rotation_quaternion()) < 0.08, "%s keeps the authored pose while running." % bone)
	var left_foot := skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin
	var hips := skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
	_expect(hips.y - left_foot.y < 0.8 and hips.y - left_foot.y > 0.4, "The legs reach the floor (hips %.2f above foot)." % (hips.y - left_foot.y))
	character.velocity = Vector3(5.0, 0, 0)
	await create_timer(0.8).timeout
	_expect(absf(float(legs.travel_angle) - PI * 0.5) < 0.15, "Travel to the body's left (+X) plays the left run (%.2f)." % legs.travel_angle)
	character.velocity = Vector3(-5.0, 0, -5.0)
	await create_timer(0.8).timeout
	_expect(absf(float(legs.travel_angle) + PI * 0.75) < 0.15, "Backward-right travel plays the backward-right run (%.2f)." % legs.travel_angle)
	character.velocity = Vector3.ZERO
	await create_timer(0.6).timeout
	_expect(float(legs.weight) < 0.01, "Standing hands the legs back to the authored idle.")
	await _dodge_checks(character, driver, skeleton)
	print("Leg clip tests: %d failure(s)." % failures)
	quit(failures)


func _dodge_checks(character: CharacterBody3D, driver: Node, skeleton: Skeleton3D) -> void:
	var guard := SkeletonModifier3D.new()
	guard.name = "BodyAim"
	skeleton.add_child(guard)
	character.velocity = Vector3(0, 0, 5.0)
	await create_timer(0.3).timeout
	_expect(driver.play_dodge(Vector3(0, 0, 1), 0.5), "A roll starts.")
	_expect(driver.is_dodging(), "The driver reports the dodge.")
	_expect(not guard.active, "Aim modifiers sleep during the dodge.")
	var upside_down := [false]
	# Poses are read right after the modifiers ran for the frame.
	skeleton.skeleton_updated.connect(func() -> void:
		var up := skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).basis * Vector3.UP
		upside_down[0] = upside_down[0] or up.y < 0.2)
	for i in 20:
		await create_timer(0.03).timeout
	_expect(upside_down[0], "The roll tips the hips over.")
	await create_timer(0.5).timeout
	await create_timer(0.3).timeout
	_expect(not driver.is_dodging() and guard.active, "The dodge ends and wakes the aim modifiers.")
	driver.dodge_style = 1
	_expect(driver.play_dodge(Vector3(1, 0, 0), 0.5), "A strafe jump starts.")
	_expect(driver.legs.get("_dodge") == "Dodge_Strafe_Left", "Travel toward +X (left) jumps with the left clip.")
	driver.legs.call("cancel_dodge")
	_expect(driver.play_dodge(Vector3(0, 0, 1), 0.5), "A forward strafe jump starts.")
	_expect(absf(float(driver.legs.get("_dodge_yaw"))) > 1.0, "A forward dodge in strafe mode turns the body toward the side clip.")
	driver.legs.call("cancel_dodge")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
