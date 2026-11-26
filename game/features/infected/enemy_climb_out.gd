extends RefCounted
## An enemy spawned from a hole plays its Climb clip standing at its normal height (ADR-0071): the clip
## itself starts with the body under the floor and ends standing, so the floor hides what is still below
## it and the enemy really climbs out. While it climbs it has no collision, no gravity and does not move.

const CLIP := &"Climb"


## Starts the climb of a spawned enemy; returns its length, 0.0 when it has no Climb clip or was placed.
static func begin(actor: Node, animation: Node) -> float:
	if animation == null or not actor.has_meta(&"spawned_by"):
		return 0.0
	animation.call("prepare_visual")
	var length := float(animation.call("play_named_one_shot", CLIP, 0.0, randf_range(0.92, 1.08)))
	if length <= 0.0:
		return 0.0
	# Without this the rest pose (a standing body) shows for the first frames, before the clip is evaluated.
	(animation.get("animation_player") as AnimationPlayer).advance(0.0)
	var body := actor as CollisionObject3D
	body.global_position.y += _capsule_height(actor) * 0.5 + 0.02 # the spawner places it at floor level
	actor.set_meta(&"emerge_mask", body.collision_mask)
	body.collision_mask = 0 # the floor would push the body while the clip still has it below the surface
	return length


## One physics tick of the climb: returns the time left, 0.0 once the climb is over and the enemy is back on gravity.
static func step(actor: CharacterBody3D, left: float, delta: float) -> float:
	actor.velocity = Vector3.ZERO
	if left - delta > 0.0:
		return left - delta
	actor.collision_mask = actor.get_meta(&"emerge_mask")
	return 0.0


static func _capsule_height(actor: Node) -> float:
	var shape_node := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		return (shape_node.shape as CapsuleShape3D).height
	return 2.0
