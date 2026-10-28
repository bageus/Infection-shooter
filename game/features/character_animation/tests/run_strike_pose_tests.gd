extends SceneTree
## Procedural melee strike pose (ADR-0066): keyed directions and the bone pose.

const POSE := preload("res://game/features/character_animation/strike_pose.gd")
const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(POSE.direction_at(POSE.KICK, "RightUpLeg", 0.5).z > 0.9, "The kick swings the right thigh forward.")
	_expect(POSE.direction_at(POSE.KICK, "RightUpLeg", 0.3).y > 0.3, "The kick chambers the knee above the hip.")
	_expect(POSE.direction_at(POSE.KICK, "RightLeg", 0.3).y < -0.9, "The shin hangs under the raised knee in the chamber.")
	_expect(POSE.direction_at(POSE.KICK, "RightLeg", 0.45).z > 0.9, "The shin drives the foot forward at the strike.")
	_expect(POSE.direction_at(POSE.KICK, "RightFoot", 0.45).y > 0.9, "The toes pull up so the sole pushes forward.")
	_expect(POSE.direction_at(POSE.KICK, "RightLeg", 0.72).y < -0.9, "The leg re-chambers before it comes down.")
	_expect(is_equal_approx(POSE.drive_at(POSE.KICK_IMPACT / POSE.KICK_SECONDS + 0.02), 1.0) and POSE.drive_at(0.0) == 0.0 and POSE.drive_at(1.0) == 0.0, "The hips drive in fully at the strike and settle back.")
	_expect(POSE.direction_at(POSE.KICK, "RightUpLeg", 1.0).is_equal_approx(Vector3.DOWN), "The leg is back at rest when the kick ends.")
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
	var foot := skeleton.find_bone("RightFoot")
	var rest_z := skeleton.get_bone_global_pose(foot).origin.z
	driver.strike.set("_elapsed", 0.25 * POSE.KICK_SECONDS)
	await process_frame
	_expect(skeleton.get_bone_global_pose(foot).origin.z > rest_z + 0.1, "The right foot is thrown forward at the strike.")
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
