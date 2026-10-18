extends RefCounted
## Transient HUD presentation only; never delays or changes gameplay values.
const COUNT_STEP_SECONDS := 0.02
const WHITE_HOLD := 0.12
const WHITE_FADE := 0.28
var target := 0.0
var maximum := 100.0
var displayed := 0
var trail := 0.0
var white_alpha := 0.0
var initialized := false
var _count_clock := 0.0
var _hold := 0.0
var _white_age := WHITE_HOLD + WHITE_FADE
var _direction := 0.0


func set_value(value: float, cap: float) -> void:
	cap = maxf(1.0, cap) if is_finite(cap) else 1.0
	value = clampf(value, 0.0, cap) if is_finite(value) else 0.0
	if not initialized or not is_equal_approx(maximum, cap):
		initialized = true
		maximum = cap
		target = value
		displayed = roundi(value)
		trail = value
		white_alpha = 0.0
		_hold = 0.0
		_white_age = WHITE_HOLD + WHITE_FADE
		_count_clock = 0.0
		return
	if is_equal_approx(target, value):
		return
	var change := signf(value - target)
	if white_alpha <= 0.0 or change != _direction:
		trail = target
		_hold = WHITE_HOLD
	_direction = change
	_white_age = 0.0
	white_alpha = 1.0
	target = value


func advance(delta: float) -> void:
	delta = maxf(0.0, delta)
	if displayed != roundi(target):
		_count_clock += delta
		if _count_clock >= COUNT_STEP_SECONDS:
			# Each rendered update displays at most one integer; no queued targets.
			displayed += 1 if displayed < roundi(target) else -1
			_count_clock = minf(_count_clock - COUNT_STEP_SECONDS, COUNT_STEP_SECONDS)
	else:
		_count_clock = 0.0
	var recovery := maxf(0.0, delta - _hold)
	_hold = maxf(0.0, _hold - delta)
	trail = lerpf(trail, target, 1.0 - exp(-12.0 * recovery))
	_white_age += delta
	white_alpha = 1.0 - clampf((_white_age - WHITE_HOLD) / WHITE_FADE, 0.0, 1.0)
	if white_alpha <= 0.0:
		trail = target


func active() -> bool:
	return displayed != roundi(target) or white_alpha > 0.0
