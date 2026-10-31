extends RefCounted
## Hero spawn settings saved with the Player Spawn: automatic (carry from the linked mission)
## or manual loadout. Maps saved before this record existed load as automatic.

const WEAPON_NAMES := ["Пистолет", "Узи", "Дробовик", "Гранатомёт", "АК", "M4", "Снайперская", "Миниган"]
const SHARED_RESERVE_WEAPON := 5 ## M4 shares the reserve of AK (index 4).
const SLOT_COUNT := 3
const MAX_HEALTH := 100.0
const MAX_AMMO := 240
const MAX_ANTIDOTES := 5
const MIN_THRESHOLD := 30.0
const MAX_THRESHOLD := 95.0


static func defaults() -> Dictionary:
	return {
		"mode": "auto",
		"slots": [0, -1, -1],
		"ammo": [75, 75, 75, 75, 75, 75, 75, 75],
		"health": MAX_HEALTH,
		"threshold": MIN_THRESHOLD,
		"antidotes": 2,
		"gas_mask": false,
		"armor": false,
		"key": false,
	}


## Clamps any stored or edited values into the ranges the player accepts.
static func sanitize(raw: Dictionary) -> Dictionary:
	var clean := defaults()
	if str(raw.get("mode", "")) == "manual":
		clean.mode = "manual"
	var slots := _slots_from(raw.get("slots"))
	if not slots.is_empty():
		clean.slots = slots
	var ammo: Variant = raw.get("ammo")
	if ammo is Array and ammo.size() == WEAPON_NAMES.size():
		for index in WEAPON_NAMES.size():
			clean.ammo[index] = clampi(int(ammo[index]), 0, MAX_AMMO)
	clean.ammo[SHARED_RESERVE_WEAPON] = clean.ammo[SHARED_RESERVE_WEAPON - 1]
	clean.health = clampf(float(raw.get("health", MAX_HEALTH)), 1.0, MAX_HEALTH)
	clean.threshold = clampf(float(raw.get("threshold", MIN_THRESHOLD)), MIN_THRESHOLD, MAX_THRESHOLD)
	clean.antidotes = clampi(int(raw.get("antidotes", 2)), 0, MAX_ANTIDOTES)
	clean.gas_mask = bool(raw.get("gas_mask", false))
	clean.armor = bool(raw.get("armor", false))
	clean.key = bool(raw.get("key", false))
	return clean


## Slot 0 always holds a weapon; the other slots are empty (-1) or hold a unique weapon.
static func _slots_from(raw: Variant) -> Array:
	if not raw is Array or raw.size() != SLOT_COUNT:
		return []
	var slots: Array = []
	for value in raw:
		var index := int(value)
		if index < -1 or index >= WEAPON_NAMES.size() or (index >= 0 and slots.has(index)):
			return []
		slots.append(index)
	return slots if slots[0] >= 0 else []
