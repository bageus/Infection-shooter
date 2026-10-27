extends RefCounted
## Blood level chosen in Video settings: how much blood there is, how far the
## droplets fly and whether it is green. Static so features and presentation
## read one value without holding a scene reference.

const GREEN := 0
const COUNT := 4
# Share of droplets and decal splatters per level; level 0 keeps today's amount.
const AMOUNT := [1.0, 0.5, 1.0, 1.0]
# Droplet launch speed per level; the maximum level throws blood three times as far.
const SPEED := [1.0, 1.0, 1.0, 3.0]
const RED_COLOR := Color(0.36, 0.01, 0.01)
const GREEN_COLOR := Color(0.10, 0.42, 0.06)
## Dark centre of a wound on a body, red-black at the red levels.
const GREEN_WOUND_CORE := Color(0.01, 0.09, 0.01)

static var level := 2
## A platform that must not show red blood (children may play) pins the level to green.
static var forced_green := false


static func force_green() -> void:
	forced_green = true
	level = GREEN


static func set_level(value: int) -> void:
	level = GREEN if forced_green else clampi(value, 0, COUNT - 1)


static func is_green() -> bool:
	return level == GREEN


static func color() -> Color:
	return GREEN_COLOR if is_green() else RED_COLOR


static func scale_amount(amount: int) -> int:
	return maxi(1, roundi(amount * AMOUNT[level]))


static func scale_speed(speed: float) -> float:
	return speed * SPEED[level]
