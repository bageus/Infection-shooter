extends RefCounted
## Enemy difficulty (settings: enemy_difficulty). Scales the authored health and damage
## percents at runtime: low halves them, normal keeps them, high uses the editor maximum.

const LOW := 0
const NORMAL := 1
const HIGH := 2
## Upper end of the editor's health and damage range, in percent of the base value.
const HIGH_PERCENT := 200.0

## Set from the player's settings. Normal keeps the authored values.
static var level := NORMAL


## The percent of the base value an infected uses, given its authored percent.
static func percent(authored: float) -> float:
	match level:
		LOW:
			return authored * 0.5
		HIGH:
			return HIGH_PERCENT
	return authored
