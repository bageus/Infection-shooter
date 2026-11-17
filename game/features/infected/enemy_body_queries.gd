extends RefCounted
## Small body queries of an infected (split out of infected_capsule.gd).


## Top of the collision capsule plus a little: where stun stars circle.
static func head_height(collision_shape: CollisionShape3D) -> float:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return 1.9
	return collision_shape.position.y + capsule.height * 0.5 * absf(collision_shape.scale.y) + 0.3


## Items the body slid into are pushed along the intended motion (sliding zeroes the velocity).
static func push_contacts(actor: CharacterBody3D, intended_motion: Vector3, strength: float) -> void:
	var pushed := {}
	for i in actor.get_slide_collision_count():
		var collider := actor.get_slide_collision(i).get_collider()
		if collider != null and not pushed.has(collider) and collider.has_method("push_from_character"):
			pushed[collider] = true
			collider.call("push_from_character", actor.global_position, intended_motion, strength)
