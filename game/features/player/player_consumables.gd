extends RefCounted
## Applies consumable effectiveness without multiplying passive regeneration.
const B := preload("res://game/features/infection/public/mutation_balance.gd")

static func heal(host: Node, amount:float, source: StringName = &"")->float:
	var previous: float = host.health
	if source == &"medkit" and host.mutation_effects.call("enabled", "assimilation"):
		amount *= 1.0 + B.value("assimilation", "percent") / 100.0
	host.health=minf(host.max_health,host.health+maxf(amount,0.0))
	var gained: float = host.health-previous
	host._wound = maxf(0.0, host._wound - gained)
	if gained > 0.0:
		host.healed.emit(gained, source)
	return gained

static func add_ammo_for_weapon(host: Node, weapon_name:String,amount:int)->int:
	for weapon in host.weapons:
		if weapon.call("get_weapon_name")==weapon_name:
			return int(weapon.call("add_reserve_ammo", ceili(amount * (1.0 + B.value("assimilation", "percent") / 100.0 if host.mutation_effects.call("enabled", "assimilation") else 1.0))))
	return 0
