extends RefCounted
## Keeps the cursor aim level with the gun in small rooms.

## Height above AimPivot where the cursor ray is clamped.
const AIM_HEIGHT := 1.2


## A wall or ceiling hit above gun height would tilt the barrel up in a small room.
## Keep the same cursor ray but aim where it crosses the gun's height instead.
static func level_aim_point(hit_point: Vector3, origin: Vector3, direction: Vector3, plane_y: float) -> Vector3:
	if hit_point.y <= plane_y + 0.0001 or absf(direction.y) < 0.0001:
		return hit_point
	var t := (plane_y - origin.y) / direction.y
	if t <= 0.0:
		return hit_point
	return origin + direction * t
