extends SceneTree
## Procedural melee strike pose (ADR-0066): keyed directions and the bone pose.

const POSE := preload("res://game/features/character_animation/strike_pose.gd")
const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var impact: float = POSE.KICK_IMPACT / POSE.KICK_SECONDS
	_expect(POSE.direction_at(POSE.KICK, "LeftUpLeg", impact).z > 0.9, "The kick swings the rear (left) thigh forward.")
	_expect(POSE.direction_at(POSE.KICK, "LeftUpLeg", 0.35).y > 0.2, "The kick chambers the knee above the hip.")
	_expect(POSE.direction_at(POSE.KICK, "LeftLeg", 0.24).y < -0.7, "The shin hangs under the knee in the chamber.")
	_expect(POSE.direction_at(POSE.KICK, "LeftLeg", impact).z > 0.9, "The shin drives the foot forward at the strike.")
	_expect(POSE.direction_at(POSE.KICK, "LeftFoot", impact).y > 0.9, "The toes pull up so the sole pushes forward.")
	_expect(POSE.direction_at(POSE.KICK, "LeftUpLeg", 1.0).y < -0.7, "The leg comes back down when the kick ends.")
	_expect(POSE.direction_at(POSE.KICK, "RightUpLeg", 0.5) == Vector3.ZERO, "The standing leg is turned, not aimed.")
	_expect(POSE.sample(POSE.KICK_DATA.KICK_HIPS, impact).z > 0.2, "The hips travel forward behind the kick.")
	_expect(POSE.sample(POSE.KICK_DATA.KICK_HIPS, 0.0) == Vector3.ZERO, "The hips start where the clip is.")
	_expect(POSE.direction_at(POSE.PUNCH, "LeftArm", 0.55).z > 0.9, "The jab extends the left arm.")
	_expect(POSE.direction_at(POSE.PUNCH, "RightArm", 0.5) == Vector3.ZERO, "The jab leaves the right arm alone.")
	var character := CharacterBody3D.new()
	root.add_child(character)
	var body := MODEL.instantiate() as Node3D
	body.name = "Body"
	character.add_child(body)
	var driver := DRIVER.new()
	driver.name = "AnimationDriver"
	driver.configure_clip_selector(func() -> StringName: return &"Idle_Pistol_TwoHand")
	character.add_child(driver)
	await process_frame
	_expect(driver.play_strike(&"wave") == 0.0, "An unknown strike kind plays nothing.")
	_expect(driver.play_strike(POSE.KICK) > 0.0 and driver.is_striking(), "The kick plays on the soldier skeleton.")
	var skeleton: Skeleton3D = driver.strike.get_skeleton()
	var foot := skeleton.find_bone("LeftFoot")
	await process_frame
	var rest_z := skeleton.get_bone_global_pose(foot).origin.z
	driver.strike.set("_elapsed", POSE.KICK_IMPACT)
	await process_frame
	driver.strike.set("_elapsed", POSE.KICK_IMPACT)
	await process_frame
	_expect(driver.strike.kick_foot.z > rest_z + 0.3, "The left foot is thrown forward at the strike.")
	await create_timer(0.7).timeout
	_expect(not driver.is_striking(), "The strike ends on its own.")
	print("strike pose failures: ", failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
