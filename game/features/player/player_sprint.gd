extends RefCounted
## Sprint (Vadim, 25.11.2026): holding the sprint key while moving makes the hero run with the gun carried, not aimed.
## The aim cursor hides, the trigger does nothing, the body faces where it runs, and the baked Sprint_<gun> clip plays
## (one hand on the gun for the pistol and uzi, both hands low at the side for the long guns). Letting go of the key, stopping
## or losing control returns the normal stance and cursor; a roll in the middle of a sprint does not (no aim stance or cursor shows
## between, the arms held after the roll are the sprint's). The minigun is too heavy to sprint with: no speed bonus.

const BODY_AIM := preload("res://game/features/player/player_body_aim.gd")
const HEAVY_WEAPON := "MINIGUN"


## True while `player` sprints; presentation (clip, cursor, trigger) and speed all follow this one test.
static func active(player: CharacterBody3D) -> bool:
	if not Input.is_action_pressed("sprint") or player.input_locked or bool(player.get("_mutation_menu_open")):
		return false
	if bool((player.get("infection_runtime") as Node).call("is_control_lost")):
		return false
	var weapon: Node3D = player.get_current_weapon()
	if weapon != null and String(weapon.call("get_weapon_name")) == HEAVY_WEAPON:
		return false
	return (player.call("_move_direction") as Vector3).length_squared() > 0.0001


## Turns the body toward the aim, or, while sprinting, toward the run (the drawn gun is not aimed, so no barrel offset).
static func turn_body(player: CharacterBody3D, aim_direction: Vector3) -> void:
	var run: Vector3 = player.call("_move_direction")
	var sprinting := active(player) and run.length_squared() > 0.0001
	BODY_AIM.turn_body(player.body_visual, run.normalized() if sprinting else aim_direction, player.get_physics_process_delta_time(), 0.0 if sprinting else float(player.weapon_mount.call("barrel_yaw_offset")))
