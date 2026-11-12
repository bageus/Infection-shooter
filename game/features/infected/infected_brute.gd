extends "res://game/features/infected/infected_capsule.gd"
## Brute: now and then it lunges toward the player to close the distance.
## The lunge only moves the brute; damage still comes solely from its attack.

@export var dash_speed := 11.0
@export var dash_duration := 0.45
@export var dash_min_distance := 3.0
@export var dash_max_distance := 9.0
@export var dash_cooldown := 9.0
## Chance per second, rolled only while the cooldown has expired and the player is in the band.
@export var dash_chance_per_second := 0.08

var _dash_cooldown := 4.0
var _dash_time := 0.0


func _behaviour_tick(delta: float, target_offset: Vector3) -> void:
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	if _dash_time > 0.0:
		_dash_time = 0.0 if _blast_stun_remaining > 0.0 else _dash_time - delta
		return
	var distance := target_offset.length()
	if _dash_cooldown > 0.0 or _pending_hit >= 0.0 or _blast_stun_remaining > 0.0:
		return
	if distance < dash_min_distance or distance > dash_max_distance:
		return
	if randf() < dash_chance_per_second * delta:
		_start_dash()


func _start_dash() -> void:
	_dash_time = dash_duration
	_dash_cooldown = dash_cooldown


func is_dashing() -> bool:
	return _dash_time > 0.0


func _chase_speed(distance: float) -> float:
	return dash_speed if is_dashing() else super._chase_speed(distance)
