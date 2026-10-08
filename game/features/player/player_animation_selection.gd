extends RefCounted

const STANCE := preload("res://game/features/player/player_weapon_stance.gd")
const SPEED_DEADZONE := 0.15
const AXIS_HYSTERESIS := 0.15

var _character: CharacterBody3D
var _aim: Node3D
var _stance: STANCE
var _direction := "Forward"
var _horizontal_axis := false


func configure(character: CharacterBody3D, aim: Node3D, stance: STANCE) -> void:
	_character = character
	_aim = aim
	_stance = stance


func select_clip() -> StringName:
	var family := _weapon_family()
	var local_velocity := _aim.global_basis.orthonormalized().inverse() * _character.velocity
	if Vector2(local_velocity.x, local_velocity.z).length() <= SPEED_DEADZONE:
		if _stance.stance == STANCE.WeaponStance.LOWERED:
			return &"Idle_Pistol_Down"
		return StringName("Idle_" + family)
	_update_direction(local_velocity)
	return StringName("Walk_" + family + "_" + _direction)


func _weapon_family() -> String:
	match _stance.weapon_index:
		2:
			return "Shotgun"
		3, 4, 5, 6, 7:
			return "Launcher"
	return "Pistol_TwoHand" if _stance.stance == STANCE.WeaponStance.TWO_HAND else "Pistol_OneHand"


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
