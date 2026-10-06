extends RefCounted
## Applies prop_weight_v1 to a physical item touched by a character: a body
## push while walking into it, or a kick when the feet brush a light item.

const WEIGHT := preload("res://game/presentation/office_floor/prop_weight.gd")
const KICKABLE_LAYER := 4
# Floor/walls/props (1-2) and other kicked items (3) carry kickable items.
const KICKABLE_MASK := 7
const KICK_COOLDOWN_MS := 350


static func push(body: RigidBody3D, weight: float, character_position: Vector3, movement: Vector3, strength: float) -> bool:
	movement.y = 0.0
	if body.freeze or movement.length_squared() < 0.01:
		return false
	var direction := movement.normalized()
	var offset := body.global_position - character_position
	offset.y = 0.0
	if offset.length_squared() > 0.001:
		if offset.normalized().dot(direction) < -0.2:
			return false # The character walks away from the item.
		direction = (direction * 0.7 + offset.normalized() * 0.3).normalized()
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var gain := WEIGHT.push_velocity_change(weight, strength, movement.length(), body.linear_velocity.dot(direction), delta)
	if gain <= 0.0:
		return false
	body.sleeping = false
	body.apply_central_impulse(direction * gain * body.mass)
	return true


## Makes an item contactless for characters while it still rests on the world
## and reports the characters' touches for kicking.
static func make_kickable(body: RigidBody3D) -> void:
	body.collision_layer = KICKABLE_LAYER
	body.collision_mask = KICKABLE_MASK
	body.contact_monitor = true
	body.max_contacts_reported = maxi(body.max_contacts_reported, 4)
	body.set_meta(&"kickable_prop", true)


static func kick(body: RigidBody3D, weight: float, character: Node) -> bool:
	if body.freeze or not character is CharacterBody3D:
		return false
	var actor := character as CharacterBody3D
	var now := Time.get_ticks_msec()
	if now < int(body.get_meta(&"kick_ready_ms", 0)):
		return false
	if body.global_position.y > _feet_height(actor) + WEIGHT.KICK_REACH_HEIGHT:
		return false # Items on desks are not reached by feet.
	var walk := Vector3(actor.velocity.x, 0.0, actor.velocity.z)
	var away := body.global_position - actor.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = walk
	if away.length_squared() < 0.0001:
		return false
	var direction := away.normalized()
	if walk.length_squared() > 0.01:
		direction = (direction * 0.45 + walk.normalized() * 0.55).normalized()
	var strength := float(actor.get("push_strength")) if actor.get("push_strength") != null else 1.0
	var speed := WEIGHT.kick_speed(weight, strength, walk.length())
	body.set_meta(&"kick_ready_ms", now + KICK_COOLDOWN_MS)
	body.sleeping = false
	body.apply_central_impulse((direction + Vector3.UP * 0.28) * speed * body.mass)
	body.apply_torque_impulse(Vector3.UP.cross(direction) * speed * body.mass * 0.08)
	return true


static func _feet_height(actor: CharacterBody3D) -> float:
	for child in actor.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			var shape := child as CollisionShape3D
			var capsule := shape.shape as CapsuleShape3D
			return shape.global_position.y - capsule.height * 0.5 * shape.global_basis.y.length()
	return actor.global_position.y
