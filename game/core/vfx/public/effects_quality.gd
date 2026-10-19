extends RefCounted
## Effects quality chosen in Video settings. Static so skill and combat effects
## read one value without a scene reference. Effects scale their extras (sparks,
## smoke, lights, afterimages) by it; the base look stays the same.

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const COUNT := 3

static var level := HIGH


static func set_level(value: int) -> void:
	level = clampi(value, 0, COUNT - 1)


## True when the current quality is `minimum` or better.
static func at_least(minimum: int) -> bool:
	return level >= minimum
