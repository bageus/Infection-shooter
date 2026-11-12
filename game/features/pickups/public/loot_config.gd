extends RefCounted
## Authored loot of a crate or an infected: plain data, no scenes or physics.
## {"mode": "empty" | "manual" | "auto", "items": {item_id: count}}

const MODES: Array[String] = ["empty", "manual", "auto"]
const WEAPON_PREFIX := "weapon_"
const WEAPON_NAMES: Array[String] = ["Pistol", "Uzi", "Shotgun", "Launcher", "AK", "M4", "Sniper", "Minigun"]
const SUPPLIES: Array[String] = ["ammo_pistol", "ammo_uzi", "ammo_shotgun", "ammo_automate", "ammo_sniper", "ammo_minigun", "ammo_grenade", "medkit", "antidote", "dna", "armor", "key"]
const MAX_COUNT := 9
## Antidote is rarer than other supplies in auto loot. Grenade rounds are as rare as sniper rounds.
## Armor, DNA and keys are manual only: auto loot never rolls them.
const AUTO_WEIGHTS := {"ammo_pistol": 0.75, "ammo_uzi": 0.60, "ammo_shotgun": 0.60, "ammo_automate": 0.60, "ammo_sniper": 0.15, "ammo_minigun": 0.20, "ammo_grenade": 0.15, "medkit": 1.0, "antidote": 0.35}
## Weapon slot indices (WEAPON_NAMES order) that take each ammo id.
const AMMO_WEAPONS := {"ammo_pistol": [0], "ammo_uzi": [1], "ammo_shotgun": [2], "ammo_grenade": [3], "ammo_automate": [4, 5], "ammo_sniper": [6], "ammo_minigun": [7]}
## Crate needs: an empty reserve weighs up to 3x, medkits 0.25x at full health to 3x at zero, antidotes 2x with none and fall off with each one held.
const NEED_LOW_AMMO_BOOST := 2.0
const NEED_MEDKIT_FULL := 0.25
const NEED_MEDKIT_EMPTY := 3.0
const NEED_ANTIDOTE_NONE := 2.0
const STAT_MIN := 50.0
const STAT_MAX := 200.0


static func item_ids() -> Array[String]:
	var ids: Array[String] = SUPPLIES.duplicate()
	for index in WEAPON_NAMES.size():
		ids.append(WEAPON_PREFIX + str(index))
	return ids


static func weapon_index(item_id: String) -> int:
	return int(item_id.trim_prefix(WEAPON_PREFIX)) if item_id.begins_with(WEAPON_PREFIX) else -1


## Always returns a usable config; unknown ids, bad counts and bad modes are dropped.
static func sanitize(raw: Variant, fallback_mode: String = "empty") -> Dictionary:
	var mode := fallback_mode
	var items := {}
	if raw is Dictionary:
		var source: Dictionary = raw
		if str(source.get("mode", "")) in MODES:
			mode = str(source["mode"])
		var listed: Variant = source.get("items", {})
		if listed is Dictionary:
			for id in item_ids():
				var count := clampi(int(listed.get(id, 0)) if _number(listed.get(id, 0)) else 0, 0, MAX_COUNT)
				if count > 0:
					items[id] = count
	var config := {"mode": mode, "items": items}
	# Chance (percent) that an infected with auto loot drops anything; 100 is the usual drop and is not stored.
	if raw is Dictionary and _number((raw as Dictionary).get("chance")) and float(raw["chance"]) < 100.0:
		config["chance"] = clampf(float(raw["chance"]), 0.0, 100.0)
	return config


## Flat list of item ids to spawn for a manual config.
static func manual_list(config: Dictionary) -> Array[String]:
	var list: Array[String] = []
	var items: Dictionary = config.get("items", {})
	for id in item_ids():
		for _i in int(items.get(id, 0)):
			list.append(id)
	return list


## Auto weights without the ammo of weapons not in `carried`; null `carried` keeps every weight.
static func auto_weights(carried: Variant) -> Dictionary:
	var weights := AUTO_WEIGHTS.duplicate()
	if carried is Array:
		for id: String in AMMO_WEAPONS:
			var carries := false
			for index: int in AMMO_WEAPONS[id]:
				carries = carries or (carried as Array).has(index)
			if not carries:
				weights.erase(id)
	return weights


## Auto crate weights from the player's needs (see `needs` in loot_drop.gd). Missing keys change nothing:
## `carried` (weapon indices), `reserve` ({weapon index: 0..1 reserve fill}), `health` (0..1), `antidotes` (count).
static func crate_weights(needs: Dictionary) -> Dictionary:
	var weights := auto_weights(needs.get("carried"))
	var reserve: Dictionary = needs.get("reserve", {})
	for id: String in weights.keys():
		if not AMMO_WEAPONS.has(id):
			continue
		var fill := 1.0
		for index: int in AMMO_WEAPONS[id]:
			if reserve.has(index):
				fill = minf(fill, clampf(float(reserve[index]), 0.0, 1.0))
		weights[id] = float(weights[id]) * (1.0 + NEED_LOW_AMMO_BOOST * (1.0 - fill))
	if needs.has("health"):
		var missing := 1.0 - clampf(float(needs["health"]), 0.0, 1.0)
		weights["medkit"] = float(weights["medkit"]) * lerpf(NEED_MEDKIT_FULL, NEED_MEDKIT_EMPTY, missing)
	if needs.has("antidotes"):
		weights["antidote"] = float(weights["antidote"]) * NEED_ANTIDOTE_NONE / (1.0 + maxi(int(needs["antidotes"]), 0))
	return weights


## Random supplies for an automatic crate: two from a large crate, one from a small one.
static func auto_list(size_hint: String, weights: Dictionary = AUTO_WEIGHTS) -> Array[String]:
	var list: Array[String] = []
	for _i in (2 if size_hint == "large" else 1):
		list.append(weighted_item(randf(), weights))
	return list


## A unit-interval roll, shared by enemy and crate loot; keeps the ammo budget fixed.
static func weighted_item(unit_roll: float, weights: Dictionary) -> String:
	var total := 0.0
	for weight: float in weights.values():
		total += maxf(0.0, weight)
	var roll := clampf(unit_roll, 0.0, 0.999999) * total
	for id: String in weights:
		roll -= maxf(0.0, float(weights[id]))
		if roll < 0.0:
			return id
	return ""


static func sanitize_stats(raw: Variant) -> Dictionary:
	var stats := {"health": 100.0, "damage": 100.0}
	if raw is Dictionary:
		for key: String in stats:
			if _number(raw.get(key, 100.0)):
				stats[key] = clampf(float(raw.get(key, 100.0)), STAT_MIN, STAT_MAX)
	return stats


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
