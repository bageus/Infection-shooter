extends SceneTree
## Auto loot offers only the ammo of weapons the player carries; armor is a manual-only item.
const CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const DROP_TABLE := preload("res://game/features/pickups/public/drop_table.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pistol_only := CONFIG.auto_weights([0])
	_check(not pistol_only.has("ammo_minigun") and not pistol_only.has("ammo_sniper"), "No minigun or sniper ammo without those weapons")
	_check(not pistol_only.has("ammo_automate") and not pistol_only.has("ammo_grenade"), "No AK/M4 or launcher ammo without those weapons")
	_check(pistol_only.has("ammo_pistol") and pistol_only.has("medkit"), "Carried ammo and supplies stay")
	_check(CONFIG.auto_weights([4]).has("ammo_automate") and not CONFIG.auto_weights([4]).has("ammo_minigun"), "AK carries the shared AK/M4 ammo")
	_check(CONFIG.auto_weights(null) == CONFIG.AUTO_WEIGHTS, "Null carried list keeps every weight")
	for _i in 200:
		_check(CONFIG.auto_list("large", pistol_only).all(func(id: String) -> bool: return pistol_only.has(id)), "Auto crate rolls only carried ammo")
	_check(not CONFIG.AUTO_WEIGHTS.has("armor"), "Auto loot never rolls armor")
	_check(CONFIG.sanitize({"mode": "manual", "items": {"armor": 2}})["items"] == {"armor": 2}, "Manual armor survives sanitization")
	_check(DROP_TABLE.SCENES.has("armor"), "Armor has a pickup scene for manual drops")
	print("Loot carried tests: %d failures" % failures)
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
