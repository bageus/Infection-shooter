extends RefCounted
## Web arena shop (main menu): what is sold and the buy / rent / ad-reward rules over a profile dictionary.
## profile: {"coins": int, "ammo": {weapon: int}, "supplies": {id: int}, "owned": [weapon], "rented": [weapon]}.
## Weapons bought are kept forever, rented ones last one run; ammo and supplies are stock that runs draw from.
## An "ad" offer is free after a rewarded ad (the caller shows the ad, then calls claim_ad / rent_with_ad).

const SUPPLY_CAP := 5
## Weapon ids in the order of the player's weapon array (the grenade launcher is not sold).
const WEAPON_INDEX := {"pistol": 0, "uzi": 1, "shotgun": 2, "ak": 4, "m16": 5, "sniper": 6, "minigun": 7}
## Ammo pack per weapon: amount, coin price (0 = only for an ad), ad = also free for an ad. The AK and M16 share a pack.
const AMMO := {
	"pistol": {"amount": 60, "price": 80, "ad": false}, "uzi": {"amount": 120, "price": 140, "ad": false},
	"shotgun": {"amount": 24, "price": 0, "ad": true}, "rifle": {"amount": 90, "price": 180, "ad": false},
	"sniper": {"amount": 18, "price": 200, "ad": false}, "minigun": {"amount": 300, "price": 0, "ad": true},
}
const SUPPLIES := {
	"health": {"price": 250, "ad": true}, "antidote": {"price": 300, "ad": false},
	"armor": {"price": 350, "ad": false}, "dna": {"price": 400, "ad": false},
}
## Weapon: coin price, rent price (0 = not for coins), rent_ad = rent for an ad.
const WEAPONS := {
	"uzi": {"price": 600, "rent": 0, "rent_ad": false}, "shotgun": {"price": 1200, "rent": 300, "rent_ad": false},
	"m16": {"price": 1800, "rent": 450, "rent_ad": false}, "ak": {"price": 1900, "rent": 480, "rent_ad": false},
	"sniper": {"price": 2400, "rent": 600, "rent_ad": false}, "minigun": {"price": 3500, "rent": 0, "rent_ad": true},
}


static func new_profile() -> Dictionary:
	return {"coins": 0, "ammo": {}, "supplies": {}, "owned": [], "rented": []}


## A profile read from a save file: unknown keys dropped, counts clamped, only known weapons.
static func sanitize(raw: Variant) -> Dictionary:
	var profile := new_profile()
	if not raw is Dictionary:
		return profile
	profile["coins"] = maxi(int(raw.get("coins", 0)), 0)
	for key: String in ["ammo", "supplies"]:
		var known: Dictionary = AMMO if key == "ammo" else SUPPLIES
		if raw.get(key) is Dictionary:
			for id: String in known:
				if raw[key].has(id):
					profile[key][id] = clampi(int(raw[key][id]), 0, SUPPLY_CAP if key == "supplies" else 100000)
	for key: String in ["owned", "rented"]:
		if raw.get(key) is Array:
			for id: Variant in raw[key]:
				if str(id) in WEAPONS and str(id) not in profile[key]:
					profile[key].append(str(id))
	return profile


## "" when it can be done, else the reason (coins, cap, owned, unknown).
static func buy_ammo(profile: Dictionary, pack: String) -> String:
	return _ammo(profile, pack, false)


static func claim_ammo_ad(profile: Dictionary, pack: String) -> String:
	return _ammo(profile, pack, true)


static func _ammo(profile: Dictionary, pack: String, by_ad: bool) -> String:
	if not AMMO.has(pack):
		return "unknown"
	var offer: Dictionary = AMMO[pack]
	var problem := _pay(profile, int(offer["price"]), bool(offer["ad"]), by_ad)
	if problem.is_empty():
		profile["ammo"][pack] = int(profile["ammo"].get(pack, 0)) + int(offer["amount"])
	return problem


static func buy_supply(profile: Dictionary, id: String) -> String:
	return _supply(profile, id, false)


static func claim_supply_ad(profile: Dictionary, id: String) -> String:
	return _supply(profile, id, true)


static func _supply(profile: Dictionary, id: String, by_ad: bool) -> String:
	if not SUPPLIES.has(id):
		return "unknown"
	if int(profile["supplies"].get(id, 0)) >= SUPPLY_CAP:
		return "cap"
	var offer: Dictionary = SUPPLIES[id]
	var problem := _pay(profile, int(offer["price"]), bool(offer["ad"]), by_ad)
	if problem.is_empty():
		profile["supplies"][id] = int(profile["supplies"].get(id, 0)) + 1
	return problem


static func buy_weapon(profile: Dictionary, id: String) -> String:
	if not WEAPONS.has(id):
		return "unknown"
	if id in profile["owned"]:
		return "owned"
	var problem := _pay(profile, int(WEAPONS[id]["price"]), false, false)
	if problem.is_empty():
		profile["owned"].append(id)
	return problem


static func rent_weapon(profile: Dictionary, id: String, by_ad: bool = false) -> String:
	if not WEAPONS.has(id):
		return "unknown"
	if id in profile["owned"] or id in profile["rented"]:
		return "owned"
	var offer: Dictionary = WEAPONS[id]
	var problem := _pay(profile, int(offer["rent"]), bool(offer["rent_ad"]), by_ad)
	if problem.is_empty():
		profile["rented"].append(id)
	return problem


## Coins are spent unless the offer is claimed with an ad that it allows; "coins" when too poor, "no_offer" when unavailable.
static func _pay(profile: Dictionary, price: int, ad_offer: bool, by_ad: bool) -> String:
	if by_ad:
		return "" if ad_offer else "no_offer"
	if price <= 0:
		return "no_offer"
	if int(profile["coins"]) < price:
		return "coins"
	profile["coins"] = int(profile["coins"]) - price
	return ""


## Weapons a new run starts with besides the pistol (owned and rented), and the rentals are used up.
static func take_run_weapons(profile: Dictionary) -> Array[String]:
	var weapons: Array[String] = []
	for id: String in profile["owned"] + profile["rented"]:
		if id not in weapons:
			weapons.append(id)
	profile["rented"] = []
	return weapons
