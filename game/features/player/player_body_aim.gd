extends RefCounted
## The body turns toward the aim; the baked clips carry the arms and the weapon with it.
const BODY_TURN_RATE := 14.0
## Standing still the body swings round slower, so the feet have time to step it round.
const STAND_TURN_RATE := 7.0
const STAND_SPEED := 0.5
## Running forward the body leans into it: the full lean is reached at sprint speed.
const LEAN_DEGREES := 7.0
const LEAN_FULL_SPEED := 8.1
const LEAN_RATE := 8.0


## Eases the body yaw toward the aim so a cursor flip does not snap 180 degrees; aim_pivot (bullets) stays exact.
## `barrel_offset` is how far the drawn gun points from the body's front (radians); the body turns that much less so the barrel itself meets the aim.
static func turn_body(body: Node3D, direction: Vector3, delta: float, barrel_offset := 0.0) -> void:
	if body.has_meta(&"death_fall"):
		return
	var mover := body.get_parent() as CharacterBody3D
	var rate := STAND_TURN_RATE if mover != null and Vector2(mover.velocity.x, mover.velocity.z).length() < STAND_SPEED else BODY_TURN_RATE
	var yaw := lerp_angle(body.global_rotation.y, atan2(direction.x, direction.z) - barrel_offset, 1.0 - exp(-rate * delta))
	var forward := maxf(0.0, Vector2(mover.velocity.x, mover.velocity.z).dot(Vector2(direction.x, direction.z).normalized())) if mover != null else 0.0
	var lean := lerpf(float(body.get_meta(&"lean", 0.0)), deg_to_rad(LEAN_DEGREES) * clampf(forward / LEAN_FULL_SPEED, 0.0, 1.0), 1.0 - exp(-LEAN_RATE * delta))
	body.set_meta(&"lean", lean)
	body.global_rotation = Vector3(0.0, yaw, 0.0)
	body.rotate_object_local(Vector3.RIGHT, lean)
