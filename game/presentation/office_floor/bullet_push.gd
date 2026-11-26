extends RefCounted
## How a bullet hit shoves a movable prop (prop_weight_v1 addition, ADR-0032).
## Bullets give a bounded nudge by weight; only explosions scatter objects.
## Grenades push through their own blast. Pure rules plus one apply().

## Momentum of one hit in kg*m/s (one pellet for the shotgun).
const WEAPON_PUSH := {"PISTOL": 0.7, "UZI": 0.5, "RIFLE": 1.0, "AK": 1.0, "M4": 0.8, "SNIPER": 1.2, "MINIGUN": 0.8, "SHOTGUN": 0.1}
const DEFAULT_PUSH := 0.7
## Speed a single hit can give at most, however light the item.
const MAX_SPEED := 0.35
const FRAME_BUDGET := &"bullet_push_frame"
const FRAME_USED := &"bullet_push_used"


## Speed in m/s one hit of weapon gives an item of weight_kg.
static func speed(weapon: String, weight_kg: float) -> float:
	var push := float(WEAPON_PUSH.get(weapon.to_upper(), DEFAULT_PUSH))
	return minf(push / maxf(weight_kg, 0.05), MAX_SPEED)


const BUCKET_MOP := preload("res://game/presentation/office_floor/bucket_mop_split.gd")
## Light items that a shot throws off instead of nudging: a bottle, and a paint can or barrel (too heavy for a nudge to show on the floor).
const FLY_OFF_ITEMS := ["09_plastic_water_bottle", "15_paint_bucket", "15_barrel"]


## A shot that hits the prop: a bucket with a mop splits off its mop first, then the item is pushed.
static func shot(body: RigidBody3D, weight_kg: float, weapon: String, direction: Vector3, hit_position: Vector3, light_item := false) -> void:
	BUCKET_MOP.split(body, direction)
	apply(body, weight_kg, weapon, direction, hit_position)
	if light_item:
		fly_off(body, direction)


# Pistol and Uzi rounds only nudge paint cans and barrels; the bottle flies from any weapon.
static func flies_off(model_path: String, weapon: String) -> bool:
	if "09_plastic_water_bottle" in model_path:
		return true
	return weapon.to_upper() not in ["PISTOL", "UZI"] and FLY_OFF_ITEMS.any(func(item: String) -> bool: return item in model_path)


## A plastic bottle is light: a hit throws it off its shelf instead of nudging it (apply caps at MAX_SPEED).
static func fly_off(body: RigidBody3D, direction: Vector3) -> void:
	if body.freeze or direction.is_zero_approx():
		return
	PhysicsCost.woke(body, &"bullet")
	body.sleeping = false
	body.apply_central_impulse((direction.normalized() + Vector3.UP).normalized() * body.mass * 2.0)


## Pellets share a frame budget; position is retained for compatible callers.
static func apply(body: RigidBody3D, weight_kg: float, weapon: String, direction: Vector3, _hit_position: Vector3) -> void:
	if body.freeze or weapon.to_upper() == "GRENADE" or direction.is_zero_approx():
		return
	var frame := Engine.get_physics_frames()
	var used := float(body.get_meta(FRAME_USED, 0.0)) if int(body.get_meta(FRAME_BUDGET, -1)) == frame else 0.0
	var current := maxf(body.linear_velocity.dot(direction.normalized()), 0.0)
	var delta_speed := minf(speed(weapon, weight_kg), maxf(MAX_SPEED - current - used, 0.0))
	if delta_speed <= 0.0: return
	body.set_meta(FRAME_BUDGET, frame)
	body.set_meta(FRAME_USED, used + delta_speed)
	PhysicsCost.woke(body, &"bullet")
	body.sleeping = false
	# A central nudge avoids huge torque on small inertias and never injects vertical lift.
	body.apply_central_impulse(direction.normalized() * delta_speed * body.mass)
