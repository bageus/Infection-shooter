extends SceneTree
## Balance guardrails from the issue #250 plan: ideal time to kill (TTK) and ammo per kill for every
## weapon against every enemy, read straight from the shipped scenes, with a fixed-seed miss model.
## The numbers are printed as a table; the asserts only catch drift (an enemy easier than a weaker one,
## a weapon whose starting ammo cannot kill a Titan twice, a Hunger that takes more than a second).

const SEED := 250
const TRIALS := 2000
const HIT_RATE := 0.7 # the share of shots that land in the miss model
const GRENADE := preload("res://game/features/combat/public/grenade_explosion.gd")
const WEAPONS := ["pistol", "uzi", "shotgun", "ak_rifle", "m4_rifle", "sniper_rifle", "minigun"]
const ENEMIES := ["hunger", "revenant", "brute", "titan", "colossus", "horde"] # weakest to strongest

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var health := {}
	for enemy: String in ENEMIES:
		var node: Node = (load("res://game/features/infected/public/infected_%s.tscn" % enemy) as PackedScene).instantiate()
		health[enemy] = float(node.get("max_health"))
		node.free()
	var lines := PackedStringArray(["weapon / enemy: ideal TTK s, ideal rounds, expected rounds at %d%% hits (seed %d)" % [HIT_RATE * 100, SEED]])
	for weapon: String in WEAPONS:
		var stats := _weapon(weapon)
		var previous := 0.0
		for enemy: String in ENEMIES:
			var ttk := _ttk(stats, health[enemy])
			var rounds := _rounds(stats, health[enemy])
			lines.append("%s / %s: %.2f s, %d rounds, %.1f expected" % [weapon, enemy, ttk, rounds, _expected_rounds(stats, health[enemy])])
			_check(ttk >= previous, "%s kills %s no faster than the weaker enemy before it" % [weapon, enemy])
			previous = ttk
		_check(_ttk(stats, health["hunger"]) <= 1.0, "%s kills a Hunger within a second" % weapon)
		_check(stats["damage"] * stats["pellets"] * stats["ammo"] >= 2.0 * health["titan"], "%s starting ammo kills a Titan at least twice" % weapon)
	var launcher_total: float = float(24) * GRENADE.CREATURE_DAMAGE
	_check(launcher_total >= 2.0 * health["titan"], "Grenade launcher starting grenades (24 x blast damage) kill a Titan at least twice")
	print("\n".join(lines))
	print("TTK balance tests: %d failure(s)." % failures)
	quit(failures)


func _weapon(name: String) -> Dictionary:
	var node: Node = (load("res://game/features/combat/public/%s.tscn" % name) as PackedScene).instantiate()
	var spin: float = float(node.get("spin_up_time"))
	var magazine := int(node.get("magazine_size"))
	var stats := {
		"damage": float(node.get("bullet_damage")), "pellets": int(node.get("pellets_per_shot")),
		"rate": float(node.get("shots_per_second")), "magazine": magazine, "reload": float(node.get("reload_time")),
		"spin": spin, "ammo": magazine + int(node.get("starting_reserve_ammo")),
	}
	node.free()
	return stats


func _rounds(stats: Dictionary, health: float) -> int:
	return ceili(health / (stats["damage"] * stats["pellets"]))


## Ideal TTK: every shot lands; includes reloads (a magazine of 0 means a belt, no reload) and spin-up.
func _ttk(stats: Dictionary, health: float) -> float:
	var rounds := _rounds(stats, health)
	var time: float = float(rounds - 1) / stats["rate"] + stats["spin"]
	if stats["magazine"] > 0:
		time += float((rounds - 1) / stats["magazine"]) * stats["reload"]
	return time


## Mean rounds spent when only HIT_RATE of the shots land, over a seeded run, so it never flakes.
func _expected_rounds(stats: Dictionary, health: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var spent := 0
	for _trial in TRIALS:
		var dealt := 0.0
		while dealt < health:
			spent += 1
			if rng.randf() < HIT_RATE:
				dealt += stats["damage"] * stats["pellets"]
	return float(spent) / TRIALS


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
