extends RefCounted

enum WeaponStance { LOWERED, ONE_HAND, TWO_HAND }

const SEQUENCE_GAP := 2.0
const LOWER_AFTER := 20.0
const MOUSE_DEADZONE := 0.75

var stance: WeaponStance = WeaponStance.ONE_HAND
var weapon_index := 0
var inactive_seconds := 0.0
var _gameplay_time := 0.0
var _last_successful_shot := -INF


func select_weapon(index: int) -> void:
	weapon_index = index
	_last_successful_shot = -INF
	inactive_seconds = 0.0
	stance = WeaponStance.ONE_HAND if _allows_one_hand() else WeaponStance.TWO_HAND


func tick(delta: float, active: bool) -> void:
	_gameplay_time += maxf(delta, 0.0)
	if active:
		record_activity()
	else:
		inactive_seconds += maxf(delta, 0.0)
		if _allows_one_hand() and inactive_seconds >= LOWER_AFTER:
			stance = WeaponStance.LOWERED


func record_activity() -> void:
	inactive_seconds = 0.0
	if stance == WeaponStance.LOWERED:
		stance = WeaponStance.ONE_HAND
		_last_successful_shot = -INF


func record_mouse_motion(relative: Vector2) -> void:
	if relative.length_squared() >= MOUSE_DEADZONE * MOUSE_DEADZONE:
		record_activity()


func begin_fire_attempt() -> WeaponStance:
	var previous := stance
	record_activity()
	stance = _next_shot_stance()
	return previous


func finish_fire_attempt(fired: bool, previous: WeaponStance) -> void:
	if fired:
		_last_successful_shot = _gameplay_time
	elif previous != WeaponStance.LOWERED:
		stance = previous


func _next_shot_stance() -> WeaponStance:
	if not _allows_one_hand():
		return WeaponStance.TWO_HAND
	return WeaponStance.TWO_HAND if _gameplay_time - _last_successful_shot < SEQUENCE_GAP else WeaponStance.ONE_HAND


func _allows_one_hand() -> bool:
	return weapon_index == 0 or weapon_index == 1
