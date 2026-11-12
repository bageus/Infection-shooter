extends SceneTree
## Auto crate loot follows the player's needs: low ammo, low health, few antidotes; two items from a large crate, one from a small.
const CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var full := {"carried": [0], "reserve": {0: 1.0}, "health": 1.0, "antidotes": 0}
	var empty_ammo := {"carried": [0], "reserve": {0: 0.0}, "health": 1.0, "antidotes": 0}
	_check(CONFIG.crate_weights(empty_ammo)["ammo_pistol"] > CONFIG.crate_weights(full)["ammo_pistol"], "An empty pistol reserve raises pistol ammo weight")
	_check(not CONFIG.crate_weights(empty_ammo).has("ammo_minigun"), "Needs never add ammo of a weapon not carried")
	var hurt := {"carried": [0], "reserve": {}, "health": 0.1, "antidotes": 0}
	var healthy := {"carried": [0], "reserve": {}, "health": 1.0, "antidotes": 0}
	_check(CONFIG.crate_weights(hurt)["medkit"] > CONFIG.crate_weights(healthy)["medkit"], "Low health raises medkit weight")
	var no_antidote := {"carried": [0], "reserve": {}, "health": 1.0, "antidotes": 0}
	var stocked := {"carried": [0], "reserve": {}, "health": 1.0, "antidotes": 3}
	_check(CONFIG.crate_weights(no_antidote)["antidote"] > CONFIG.crate_weights(stocked)["antidote"], "Few antidotes raise antidote weight")
	_check(CONFIG.crate_weights({}) == CONFIG.AUTO_WEIGHTS, "Missing needs keep the authored weights")
	for _i in 200:
		_check(CONFIG.auto_list("large", CONFIG.crate_weights(empty_ammo)).size() == 2, "A large crate drops two items")
		_check(CONFIG.auto_list("small", CONFIG.crate_weights(hurt)).size() == 1, "A small crate drops one item")
	print("Crate needs tests: %d failure(s)." % failures)
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
