extends RefCounted
## The body turns toward the aim; the baked clips carry the arms and the weapon with it.
const BODY_TURN_RATE := 14.0


## Eases the body yaw toward the aim so a cursor flip does not snap 180 degrees; aim_pivot (bullets) stays exact.
static func turn_body(body: Node3D, direction: Vector3, delta: float) -> void:
	if body.has_meta(&"death_fall"):
		return
	var yaw := lerp_angle(body.global_rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-BODY_TURN_RATE * delta))
	body.global_rotation = Vector3(0.0, yaw, 0.0)
