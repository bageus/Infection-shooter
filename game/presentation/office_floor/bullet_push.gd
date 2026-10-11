extends RefCounted
## How a bullet hit shoves a movable prop (prop_weight_v1 addition, ADR-0032).
## Every weapon pushes every loose item, scaled by its weight: light items
## jump and tumble, chairs slide and turn, heavy furniture only creeps.
## Grenades push through their own blast. Pure rules plus one apply().

## Momentum of one hit in kg*m/s (one pellet for the shotgun).
const WEAPON_PUSH := {"PISTOL": 5.5, "UZI": 4.0, "RIFLE": 9.0, "SHOTGUN": 1.5}
const DEFAULT_PUSH := 5.5
## Speed a single hit can give at most, however light the item.
const MAX_SPEED := 3.2
## Items up to this weight also hop off the floor a little.
const HOP_MAX_KG := 3.0
const HOP_SHARE := 0.25


## Speed in m/s one hit of weapon gives an item of weight_kg.
static func speed(weapon: String, weight_kg: float) -> float:
	var push := float(WEAPON_PUSH.get(weapon.to_upper(), DEFAULT_PUSH))
	return minf(push / maxf(weight_kg, 0.05), MAX_SPEED)


## Shoves body along the shot; the hit point off the centre turns it too.
static func apply(body: RigidBody3D, weight_kg: float, weapon: String, direction: Vector3, hit_position: Vector3) -> void:
	if body.freeze or weapon.to_upper() == "GRENADE" or direction.is_zero_approx():
		return
	var push := direction.normalized()
	if weight_kg <= HOP_MAX_KG:
		push = (push + Vector3.UP * HOP_SHARE).normalized()
	body.sleeping = false
	body.apply_impulse(push * speed(weapon, weight_kg) * body.mass, hit_position - body.global_position)
