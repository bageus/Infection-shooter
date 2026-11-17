extends RefCounted
## Blend times the game uses between enemy clips (ADR-0071), shared with the animation page so a
## chain played there looks like the game. The extra clips start from poses far from the base
## idle, so they cross-fade longer than the 0.12 s of plain locomotion.

const AFTER_ONE_SHOT := 0.3 # back to idle or locomotion after an attack, turn or climb


## Seconds to cross-fade into `clip`; `after_one_shot` when a one-shot clip just ended.
static func seconds(clip: String, default: float, after_one_shot: bool = false) -> float:
	var blend := default
	if clip.begins_with("Idle"):
		blend = 0.3
	elif clip.begins_with("Turn"):
		blend = 0.25
	elif clip.begins_with("Attack") or clip.begins_with("Death"):
		blend = 0.2
	return maxf(blend, AFTER_ONE_SHOT) if after_one_shot else blend
