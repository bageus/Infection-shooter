extends RefCounted
## Picks the player's baked clip: Idle_<gun>, Walk_<dir>_<gun> or Run_<dir>_<gun>, Reload_<gun> is played by the weapon mount.

const STANCE := preload("res://game/features/player/player_weapon_stance.gd")
const SPEED_DEADZONE := 0.15
const AXIS_HYSTERESIS := 0.15
## Ground speed above which the run cycle plays (the walk cycle is a slow stealth step), and the share of it a runner keeps.
const RUN_SPEED := 1.8
const RUN_EXIT_RATIO := 0.85
## Clip suffix per weapon index (pistol, uzi, shotgun, launcher, AK, M4, sniper, minigun).
## Turning on the spot: the body is this far (degrees) from the aim, so the walk cycle steps it round at a
## slow shuffle speed (it also drives the quiet foot taps); the step is kept for a moment so a cycle completes.
const TURN_DEGREES := 10.0
const TURN_HOLD_SECONDS := 0.4
const TURN_STEP_SPEED := 0.7
const FAMILIES := ["Pistol", "Uzi", "Shotgun", "Launcher", "AK", "M4", "Sniper", "Minigun"]

var _character: CharacterBody3D
var _aim: Node3D
var _stance: STANCE
var _direction := "Forward"
var _horizontal_axis := false
var _running := false
var _turn_until := 0.0
## Signed angle (radians, positive turns left) the body still has to swing to meet the aim.
var _turn_error := 0.0
var _diagonal: SkeletonModifier3D


func configure(character: CharacterBody3D, aim: Node3D, stance: STANCE) -> void:
	_character = character
	_aim = aim
	_stance = stance


func select_clip() -> StringName:
	var family := family_of(_stance.weapon_index)
	var local_velocity := _aim.global_basis.orthonormalized().inverse() * _character.velocity
	var speed := Vector2(local_velocity.x, local_velocity.z).length()
	var driver := _character.get_node_or_null("AnimationDriver")
	var turning := speed <= SPEED_DEADZONE and _turning_in_place()
	# The baked turn clips (all but the arms) swing the hero round on the spot; without them the walk cycle shuffles him.
	var turn_clip := turning and driver != null and driver.has_method("play_turn") and bool(driver.call("play_turn", &"left" if _turn_error > 0.0 else &"right"))
	if driver != null:
		driver.set("turn_step_speed", TURN_STEP_SPEED if turning and not turn_clip else 0.0)
	if turn_clip:
		_running = false
		_blend_diagonal(&"", 0.0)
		return StringName("Idle_" + family)
	if turning or speed <= SPEED_DEADZONE:
		_running = false
		_blend_diagonal(&"", 0.0)
		return StringName(("Walk_Forward_" if turning else "Idle_") + family)
	_running = speed > RUN_SPEED * (RUN_EXIT_RATIO if _running else 1.0)
	_update_direction(local_velocity)
	var gait := "Run_" if _running else "Walk_"
	# The other axis of a diagonal: its share is 0 straight along the main axis and 0.5 at 45 degrees.
	var across := ("Forward" if local_velocity.z <= 0.0 else "Backward") if _horizontal_axis else ("Right" if local_velocity.x >= 0.0 else "Left")
	var major := absf(local_velocity.x if _horizontal_axis else local_velocity.z)
	var minor := absf(local_velocity.z if _horizontal_axis else local_velocity.x)
	_blend_diagonal(StringName(gait + across + "_" + family), clampf(atan2(minor, major) / (PI * 0.5), 0.0, 0.5))
	return StringName(gait + _direction + "_" + family)


func _blend_diagonal(clip: StringName, weight: float) -> void:
	if _diagonal == null:
		var driver := _character.get_node_or_null("AnimationDriver")
		var body := _character.get_node_or_null("Body")
		var skeletons := body.find_children("*", "Skeleton3D", true, false) if body != null else []
		if driver == null or skeletons.is_empty() or driver.get("animation_player") == null:
			return
		_diagonal = preload("res://game/features/player/player_diagonal_legs.gd").new()
		_diagonal.name = "DiagonalLegs"
		_diagonal.set("player", driver.get("animation_player"))
		(skeletons[0] as Node).add_child(_diagonal)
	_diagonal.set("clip", clip)
	_diagonal.set("weight", weight)


func _turning_in_place() -> bool:
	# The model looks along +Z, the aim pivot along -Z.
	var body := _character.get("body_visual") as Node3D
	if body == null:
		return false
	var mount := _character.get("weapon_mount") as Node
	var held_off := float(mount.get("barrel_offset")) if mount != null else 0.0
	var signed_error := angle_difference(body.global_rotation.y, _aim.global_rotation.y + PI - held_off)
	var error := absf(signed_error)
	var now := Time.get_ticks_msec() * 0.001
	if error > deg_to_rad(TURN_DEGREES):
		_turn_until = now + TURN_HOLD_SECONDS
		_turn_error = signed_error
	return now < _turn_until


static func family_of(weapon_index: int) -> String:
	return FAMILIES[clampi(weapon_index, 0, FAMILIES.size() - 1)]


func _update_direction(local_velocity: Vector3) -> void:
	var horizontal := absf(local_velocity.x)
	var forward := absf(local_velocity.z)
	var margin := maxf(horizontal, forward) * AXIS_HYSTERESIS
	if horizontal > forward + margin:
		_horizontal_axis = true
	elif forward > horizontal + margin:
		_horizontal_axis = false
	if _horizontal_axis:
		_direction = "Right" if local_velocity.x >= 0.0 else "Left"
	else:
		_direction = "Forward" if local_velocity.z <= 0.0 else "Backward"
