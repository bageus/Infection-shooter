extends SceneTree
## The hero's baked Mixamo clips (tools/build_hero_clips.gd): turns on the spot, the kick and the deaths.

const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")
const CLIPS_API := preload("res://game/features/character_animation/hero_body_clips.gd")
const CLIPS := preload("res://models/objects/characters/hero_extra_clips.res")
const LEG_OVERLAY := preload("res://game/features/character_animation/leg_overlay.gd")

var failures := 0


## Records bone poses where the modifiers leave them (the skeleton gives back the unmodified pose outside its update).
class Probe extends SkeletonModifier3D:
	var foot := Vector3.ZERO
	var hand := Basis.IDENTITY
	var hips := Vector3.ZERO
	var hips_basis := Basis.IDENTITY
	var spine_basis := Basis.IDENTITY


	func _process_modification() -> void:
		var skeleton := get_skeleton()
		foot = skeleton.get_bone_global_pose(skeleton.find_bone("RightFoot")).origin
		hand = skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).basis.orthonormalized()
		hips = skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
		hips_basis = skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).basis.orthonormalized()
		spine_basis = skeleton.get_bone_global_pose(skeleton.find_bone("Spine")).basis.orthonormalized()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for clip in ["Turn_Left", "Turn_Right", "Kick", "Death_FromRight", "Death_Dying", "Death_HitToBack"]:
		_expect(CLIPS.has_animation(clip), "The library holds %s." % clip)
	_expect(float(CLIPS.get_animation("Turn_Left").get_meta("turn_yaw")) > 0.7, "Turn_Left turns the body left (positive yaw).")
	_expect(float(CLIPS.get_animation("Turn_Right").get_meta("turn_yaw")) < -0.7, "Turn_Right turns the body right (negative yaw).")
	var character := CharacterBody3D.new()
	root.add_child(character)
	var body := MODEL.instantiate() as Node3D
	body.name = "Body"
	character.add_child(body)
	var driver := DRIVER.new()
	driver.name = "AnimationDriver"
	driver.extra_clips = CLIPS
	driver.configure_clip_selector(func() -> StringName: return &"Idle_Pistol")
	character.add_child(driver)
	await process_frame
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var before := Probe.new() # runs before the body clip: the base clip's pose
	skeleton.add_child(before)
	await process_frame
	var rest_foot := before.foot
	_expect(driver.strike_impact_time(&"kick", 0.27) > 0.2 and driver.strike_impact_time(&"kick", 0.27) < 0.6, "The kick lands where its clip puts the foot (%.2f s)." % driver.strike_impact_time(&"kick", 0.27))
	var length: float = driver.play_strike(&"kick")
	_expect(length > 0.8 and driver.is_striking() and driver.is_body_clip_playing(), "The kick plays as a body clip (%.2f s)." % length)
	var after := Probe.new() # after it
	skeleton.add_child(after)
	var forward := 0.0
	var arm_drift := 0.0
	var started := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - started) * 0.001 < length * 0.9:
		await process_frame
		forward = maxf(forward, after.foot.z - rest_foot.z)
		arm_drift = maxf(arm_drift, (after.hand * before.hand.inverse()).get_rotation_quaternion().get_angle())
	_expect(forward > 0.3, "The right foot is thrown forward during the kick (%.2f m)." % forward)
	_expect(arm_drift < 0.2, "The arms keep their grip through the kick (%.2f rad)." % arm_drift)
	await create_timer(length * 0.3 + 0.3).timeout
	_expect(not driver.is_striking(), "The kick ends on its own.")
	_expect(driver.play_turn(&"left") and driver.is_body_clip_playing(), "A left turn plays.")
	_expect(driver.body_clip.get("_animation") == driver.animation_player.get_animation("Turn_Left"), "The left turn uses Turn_Left.")
	_expect(not "Head" in driver.body_clip.bones and not "Spine" in driver.body_clip.bones, "A turn on the spot leaves the head and torso to the game.")
	await create_timer(1.0).timeout
	_expect(driver.play_turn(&"left"), "A new turn starts after the first one ended.")
	var turn_start: float = driver.body_clip.get("_time")
	for _step in 30: # still turning: asking again keeps the one clip going, past the length of a pass and without a restart
		await create_timer(0.05).timeout
		driver.play_turn(&"left")
	_expect(driver.is_body_clip_playing() and float(driver.body_clip.get("_time")) > turn_start + 1.4, "A turn that goes on keeps its clip going (%.2f s)." % float(driver.body_clip.get("_time")))
	_expect(not driver.play_turn(&"around"), "An unknown side plays nothing.")
	# Legs kept on a strafe cycle under another clip (a reload on the move) bring the cycle's pelvis along, the torso stays.
	var legs := LEG_OVERLAY.attach(body)
	var last := Probe.new() # after the legs
	skeleton.add_child(last)
	legs.follow(driver.animation_player.get_animation("Run_Right_Pistol"), 1.0)
	await create_timer(0.5).timeout
	_expect(last.hips_basis.get_rotation_quaternion().angle_to(before.hips_basis.get_rotation_quaternion()) > 0.4, "The legs' cycle turns the pelvis with them.")
	_expect(last.spine_basis.get_rotation_quaternion().angle_to(before.spine_basis.get_rotation_quaternion()) < 0.05, "The torso keeps the pose of the clip underneath.")
	legs.stop()
	await create_timer(1.0).timeout
	_expect(not driver.is_body_clip_playing(), "The turn ends on its own.")
	var standing := after.hips.y
	var death: float = driver.play_death_clip()
	_expect(death > 1.5 and driver.play_death_clip() == 0.0, "One death clip plays, once (%.2f s)." % death)
	await create_timer(death + 0.3).timeout
	var lying := after.hips.y
	_expect(lying < standing - 0.4, "The dead hero's hips end low (%.2f -> %.2f)." % [standing, lying])
	_expect(driver.play_strike(&"kick") == 0.0 and not driver.play_turn(&"left"), "A dead hero neither kicks nor turns.")
	# The fall backward ends in a ragdoll that lies on the floor.
	CLIPS_API.release_ragdoll(driver)
	_expect(driver.ragdoll != null and driver.ragdoll.get_child_count() >= 10, "The ragdoll builds a volume per main bone.")
	await create_timer(1.5).timeout
	_expect(is_instance_valid(driver.ragdoll) and driver.ragdoll.active and after.hips.y < standing - 0.4, "The ragdoll keeps lying low (%.2f)." % after.hips.y)
	print("hero clips failures: ", failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: ", message)
