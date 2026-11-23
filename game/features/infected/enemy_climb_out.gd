extends RefCounted
## An enemy spawned from a hole starts its Climb clip under the floor (ADR-0071). While it climbs it
## has no collision and is moved by hand: the origin rises from its spawn depth to the standing height
## over the clip's second part, so the body comes out of the floor as the clip plays. No gravity.

const CLIP := &"Climb"
const RISE_FROM := 0.35 # clip progress where the origin starts to rise


## Origin height for a spawned enemy: a whole capsule below the floor, so the body starts hidden.
static func under_floor(actor: Node) -> float:
	return -_capsule_height(actor)


## Starts the climb of a spawned enemy; returns its length, 0.0 when it has no Climb clip or was placed.
static func begin(actor: Node, animation: Node) -> float:
	if animation == null or not actor.has_meta(&"spawned_by"):
		return 0.0
	animation.call("prepare_visual")
	var length := float(animation.call("play_named_one_shot", CLIP, 0.0, randf_range(0.92, 1.08)))
	if length <= 0.0:
		return 0.0
	var body := actor as CollisionObject3D
	body.global_position.y += under_floor(actor) # placed at floor level by the spawner
	actor.set_meta(&"emerge_mask", body.collision_mask)
	actor.set_meta(&"emerge_from", body.global_position.y)
	actor.set_meta(&"emerge_length", length)
	body.collision_mask = 0 # the floor would push the body up while it starts below it
	return length


## One physics tick of the climb: returns the time left, 0.0 once the climb is over and the enemy is back on gravity.
static func step(actor: CharacterBody3D, left: float, delta: float) -> float:
	actor.velocity = Vector3.ZERO
	var length: float = actor.get_meta(&"emerge_length")
	var progress := 1.0 - left / length
	var rise := smoothstep(RISE_FROM, 1.0, progress)
	actor.global_position.y = lerpf(actor.get_meta(&"emerge_from"), _capsule_height(actor) * 0.5 + 0.02, rise)
	if left - delta > 0.0:
		return left - delta
	actor.collision_mask = actor.get_meta(&"emerge_mask")
	return 0.0


static func _capsule_height(actor: Node) -> float:
	var shape_node := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		return (shape_node.shape as CapsuleShape3D).height
	return 2.0
