extends RefCounted
## An enemy spawned from a hole starts its Climb clip, which begins below the floor, and stands
## still until it is out (ADR-0070); the spawner faces each one away from the hole.

const CLIP := &"Climb"


## Starts the climb of a spawned enemy; returns its length, 0.0 when it has no Climb clip or was placed.
static func begin(actor: Node, animation: Node) -> float:
	if animation == null or not actor.has_meta(&"spawned_by"):
		return 0.0
	animation.call("prepare_visual")
	return float(animation.call("play_named_one_shot", CLIP, 0.0, randf_range(0.92, 1.08)))


## One physics tick of the climb: no walking, only gravity; returns the time left.
static func step(actor: CharacterBody3D, left: float, delta: float) -> float:
	actor.velocity.x = 0.0
	actor.velocity.z = 0.0
	actor.call("_apply_gravity", delta)
	actor.move_and_slide()
	return left - delta
