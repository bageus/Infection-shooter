extends RefCounted
## A kick or heavy punch breaks a loot crate, and its pieces fly apart. A heavy punch
## bursts the crate like a blast, so the splinters scatter in every direction; a kick
## breaks it the way a shotgun blast does.
const BLOW := 500.0 # Far above a crate's health; the weapon multiplier still breaks it in one blow.


static func break_crate(prop: Node3D, hit_position: Vector3, direction: Vector3, burst: bool) -> void:
	if "02_crate_canvas_large" in str(prop.get("model_path")):
		return # Tarp-covered crates are indestructible.
	# The blast weapon tag makes the break a full one, with pieces thrown outward from the hit.
	prop.call("take_projectile_hit", BLOW, hit_position, Vector3.UP, direction, "GRENADE" if burst else "SHOTGUN")
