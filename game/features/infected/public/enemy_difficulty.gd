extends RefCounted
## Enemy difficulty (settings: enemy_difficulty). Scales the authored health and damage
## percents at runtime: low halves them, normal keeps them, high doubles them.
## Every level keeps the authored order, so a higher health percent is never easier.

const LOW := 0
const NORMAL := 1
const HIGH := 2
const HIGH_MULTIPLIER := 2.0

## Set from the player's settings. Normal keeps the authored values.
static var level := NORMAL


## The percent of the base value an infected uses, given its authored percent.
static func percent(authored: float) -> float:
	match level:
		LOW:
			return authored * 0.5
		HIGH:
			return authored * HIGH_MULTIPLIER
	return authored
