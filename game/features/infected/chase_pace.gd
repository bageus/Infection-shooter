extends RefCounted
## Chase state uses continuous running; the body still owns attacks, stun,
## injury/ability modifiers and collision-limited movement.
var charging := false
var speed := 0.0

func _init(_seed_value: int = 0) -> void:
	pass

func tick(_delta: float, _distance: float, _charge_distance: float, move_speed: float, _walk_factor: float) -> float:
	charging = true
	speed = move_speed
	return speed


## Non-stacking hit drag; a burst cannot stop the chase or extend a stun.
var hit_penalty := 0.0


func hit(amount: float, max_health: float) -> float:
	var strength := clampf(amount / maxf(max_health * 0.2, 1.0), 0.12, 1.1)
	hit_penalty = maxf(hit_penalty, strength * 0.14)
	return strength


func recover_hit(delta: float) -> void:
	hit_penalty = move_toward(hit_penalty, 0.0, maxf(delta, 0.0) * 0.95)
