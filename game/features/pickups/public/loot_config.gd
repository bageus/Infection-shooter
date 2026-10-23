extends RefCounted
## Authored loot of a crate or an infected: plain data, no scenes or physics.
## {"mode": "empty" | "manual" | "auto", "items": {item_id: count}}

const MODES: Array[String] = ["empty", "manual", "auto"]
const WEAPON_PREFIX := "weapon_"
const WEAPON_NAMES: Array[String] = ["Pistol", "Uzi", "Shotgun", "Launcher", "AK", "M4", "Sniper", "Minigun"]
const SUPPLIES: Array[String] = ["ammo_pistol", "ammo_uzi", "ammo_shotgun", "ammo_automate", "ammo_sniper", "ammo_minigun", "ammo_grenade", "medkit", "antidote", "dna"]
const MAX_COUNT := 9
## Antidote and DNA are rarer than other supplies in auto loot. Grenade rounds are as rare as sniper rounds.
const AUTO_WEIGHTS := {"ammo_pistol": 0.75, "ammo_uzi": 0.60, "ammo_shotgun": 0.60, "ammo_automate": 0.60, "ammo_sniper": 0.15, "ammo_minigun": 0.20, "ammo_grenade": 0.15, "medkit": 1.0, "antidote": 0.35, "dna": 0.2}
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
	return {"mode": mode, "items": items}


## Flat list of item ids to spawn for a manual config.
static func manual_list(config: Dictionary) -> Array[String]:
	var list: Array[String] = []
	var items: Dictionary = config.get("items", {})
	for id in item_ids():
		for _i in int(items.get(id, 0)):
			list.append(id)
	return list


## Random supplies for an automatic crate; bigger crates hold more.
static func auto_list(size_hint: String) -> Array[String]:
	var list: Array[String] = []
	var count := randi_range(2, 4) if size_hint == "large" else randi_range(1, 2)
	for _i in count:
		list.append(weighted_item(randf(), AUTO_WEIGHTS))
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
