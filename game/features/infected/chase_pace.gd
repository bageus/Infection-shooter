extends RefCounted
## Stalk/charge pace of a hunting infected (ADR-0040). Beyond charge range it
## stalks at walking pace. Inside it charges in bursts: a sprint of a few
## seconds, then it drops back to a walk to recover before the next burst.
## Near the prey it always charges (the final lunge). Changes of pace are eased,
## so the animation crossfades between walk and run instead of snapping.

## Seconds of one sprint and of the walk that follows it (random in range).
var charge_seconds := Vector2(2.4, 4.2)
var recover_seconds := Vector2(1.1, 2.2)
## Within this distance (m) the infected never drops to a walk.
var lunge_distance := 3.5
## Charge range is left only this far (m) beyond it, so the pace does not
## flicker at its edge.
var hysteresis := 1.5
## Speeding up and slowing down, in move speeds per second.
var acceleration := 1.4
var deceleration := 1.0

var charging := false
var speed := 0.0
var _in_range := false
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


## Advances the pace and returns the chase speed (m/s) before injuries.
## charge_distance <= 0 charges at full speed all the time.
func tick(delta: float, distance: float, charge_distance: float, move_speed: float, walk_factor: float) -> float:
	if charge_distance <= 0.0:
		charging = true
		speed = move_speed
		return speed
	var in_range := distance <= charge_distance + (hysteresis if _in_range else 0.0)
	if in_range and not _in_range:
		_start(true)
	_in_range = in_range
	if not in_range:
		charging = false
	elif distance <= lunge_distance:
		charging = true
		_timer = maxf(_timer, 0.5)
	else:
		_timer -= delta
		if _timer <= 0.0:
			_start(not charging)
	var walk := move_speed * walk_factor
	var wanted := move_speed if charging else walk
	var rate := (acceleration if wanted > speed else deceleration) * move_speed
	# Setting off from a standstill goes straight to walking pace.
	speed = move_toward(maxf(speed, walk), wanted, rate * delta)
	return speed


func _start(charge: bool) -> void:
	charging = charge
	var span := charge_seconds if charge else recover_seconds
	_timer = _rng.randf_range(span.x, span.y)
