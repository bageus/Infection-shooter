extends RefCounted
## Picks the player's baked clip: Idle_<gun>, Walk_<dir>_<gun> or Run_<dir>_<gun>, Reload_<gun> is played by the weapon mount.

const STANCE := preload("res://game/features/player/player_weapon_stance.gd")
const SPEED_DEADZONE := 0.15
const AXIS_HYSTERESIS := 0.15
## Ground speed above which the run cycle plays (the walk cycle is a slow stealth step), and the share of it a runner keeps.
const RUN_SPEED := 1.8
const RUN_EXIT_RATIO := 0.85
## Clip suffix per weapon index (pistol, uzi, shotgun, launcher, AK, M4, sniper, minigun).
const FAMILIES := ["Pistol", "Uzi", "Shotgun", "Launcher", "AK", "M4", "Sniper", "Minigun"]

var _character: CharacterBody3D
var _aim: Node3D
var _stance: STANCE
var _direction := "Forward"
var _horizontal_axis := false
var _running := false


func configure(character: CharacterBody3D, aim: Node3D, stance: STANCE) -> void:
	_character = character
	_aim = aim
	_stance = stance


func select_clip() -> StringName:
	var family := family_of(_stance.weapon_index)
	var local_velocity := _aim.global_basis.orthonormalized().inverse() * _character.velocity
	var speed := Vector2(local_velocity.x, local_velocity.z).length()
	if speed <= SPEED_DEADZONE:
		_running = false
		return StringName("Idle_" + family)
	_running = speed > RUN_SPEED * (RUN_EXIT_RATIO if _running else 1.0)
	_update_direction(local_velocity)
	return StringName(("Run_" if _running else "Walk_") + _direction + "_" + family)


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
