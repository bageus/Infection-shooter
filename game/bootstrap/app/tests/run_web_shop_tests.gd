extends SceneTree
## Web arena shop rules: coins, ad offers, caps, owned and rented weapons.

const SHOP := preload("res://game/bootstrap/app/web_shop.gd")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	var p := SHOP.new_profile()
	_check(SHOP.buy_ammo(p, "pistol") == "coins", "no coins, no ammo")
	p["coins"] = 1000
	_check(SHOP.buy_ammo(p, "pistol").is_empty() and p["coins"] == 920 and p["ammo"]["pistol"] == 60, "pistol ammo +60 for 80")
	_check(SHOP.buy_ammo(p, "shotgun") == "no_offer", "shotgun ammo is only for an ad")
	_check(SHOP.claim_ammo_ad(p, "shotgun").is_empty() and p["coins"] == 920 and p["ammo"]["shotgun"] == 24, "an ad gives the shotgun ammo free")
	_check(SHOP.claim_ammo_ad(p, "pistol") == "no_offer", "no ad offer for pistol ammo")
	_check(SHOP.buy_supply(p, "health").is_empty() and p["supplies"]["health"] == 1 and p["coins"] == 670, "a medkit costs 250")
	_check(SHOP.claim_supply_ad(p, "health").is_empty() and p["supplies"]["health"] == 2, "a medkit for an ad")
	p["supplies"]["health"] = 5
	_check(SHOP.buy_supply(p, "health") == "cap" and p["coins"] == 670, "supplies stack to 5, nothing is charged")
	_check(SHOP.buy_weapon(p, "shotgun") == "coins", "a shotgun is too expensive")
	p["coins"] = 2000
	_check(SHOP.buy_weapon(p, "shotgun").is_empty() and "shotgun" in p["owned"] and p["coins"] == 800, "buy a shotgun for 1200")
	_check(SHOP.buy_weapon(p, "shotgun") == "owned" and SHOP.rent_weapon(p, "shotgun") == "owned", "an owned weapon is not sold or rented again")
	_check(SHOP.rent_weapon(p, "ak").is_empty() and p["coins"] == 320 and "ak" in p["rented"], "rent an AK for 480")
	_check(SHOP.rent_weapon(p, "minigun") == "no_offer" and SHOP.rent_weapon(p, "minigun", true).is_empty(), "the minigun is rented only for an ad")
	var weapons := SHOP.take_run_weapons(p)
	_check(weapons == ["ak", "minigun"] and p["rented"].is_empty() and p["owned"] == ["shotgun"], "a run takes rented weapons first, two slots, rentals are used up")
	p["rented"].append("sniper")
	_check(SHOP.take_run_weapons(p) == ["sniper", "shotgun"], "owned weapons fill the free slots")
	p["rented"] = ["m16", "ak", "sniper"]
	_check(SHOP.take_run_weapons(p) == ["m16", "ak"] and p["rented"] == ["sniper"], "a rental without a free slot stays rented")
	_check(SHOP.buy_ammo(p, "nope") == "unknown", "unknown packs are refused")
	var loaded := SHOP.sanitize({"coins": -5, "ammo": {"pistol": 7, "bogus": 1}, "supplies": {"health": 99}, "owned": ["ak", "ak", "rpg"], "rented": "x"})
	_check(loaded["coins"] == 0 and loaded["ammo"] == {"pistol": 7} and loaded["supplies"]["health"] == 5 and loaded["owned"] == ["ak"] and loaded["rented"].is_empty(), "a save file is repaired")
	print("web shop tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
