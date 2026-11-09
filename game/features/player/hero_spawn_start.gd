extends RefCounted
## Start state of the hero from a manual planner spawn, set through the player's own public methods.


static func apply(player: Node, hero: Dictionary) -> void:
	player.health = clampf(float(hero.health), 1.0, player.max_health)
	player.antidotes = clampi(int(hero.antidotes), 0, player.max_antidotes)
	player.import_loadout({"slots": hero.slots, "armor": player.max_armor * float(hero.armor), "ammo": hero.ammo})
	var infection: Node = player.infection_runtime
	infection.call("restore_critical_threshold", float(hero.threshold))
	# The gas mask is never on at level start (main.gd resets it), so the planner's gas mask setting is not applied.
	# shortcut: no key item exists yet, so the key setting is saved but not applied.
