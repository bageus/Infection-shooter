extends RefCounted
## A kick or heavy punch breaks a loot crate the way a shotgun blast does, so the
## pieces fly apart instead of settling into the floor.
const BLOW := 500.0 # Far above a crate's health; the shotgun multiplier still breaks it in one blow.


static func break_crate(prop: Node3D, hit_position: Vector3, direction: Vector3) -> void:
	if "02_crate_canvas_large" in str(prop.get("model_path")):
		return # Tarp-covered crates are indestructible.
	prop.call("take_projectile_hit", BLOW, hit_position, Vector3.UP, direction, "SHOTGUN")
