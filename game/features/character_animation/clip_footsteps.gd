extends RefCounted
## Footstep timing of the player's baked walk and run cycles: the playback phases (0..1) at which the
## left and right foot land. Read off the ankle heights of the Walk_*/Run_* clips.
const CONTACTS := {"Walk": [0.55, 0.05], "Run": [0.2, 0.75]}


## Side (0 left, 1 right) of the foot that landed between two playback phases, -1 when none did.
static func step_side(gait: String, previous: float, current: float) -> int:
	var contacts: Array = CONTACTS.get(gait, [])
	for side in contacts.size():
		var phase: float = contacts[side]
		var crossed := (previous < phase and current >= phase) if current >= previous else (previous < phase or current >= phase)
		if crossed:
			return side
	return -1
