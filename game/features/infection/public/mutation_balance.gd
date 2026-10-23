extends RefCounted
## Immutable skill tuning shared by gameplay and localized card templates.
const VALUES := {
	"muscle_memory": {
		"percent": 30
	},
	"stabilizers": {
		"percent": 30
	},
	"combat_reflex": {
		"percent": 30,
		"duration": 3
	},
	"claws": {
		"damage": 25,
		"interval": 3,
		"radius": 1.5
	},
	"blood_scent": {
		"percent": 30
	},
	"adrenaline": {
		"percent": 50,
		"duration": 4
	},
	"hypertrophy": {
		"percent": 15
	},
	"regeneration": {
		"heal": 3,
		"delay": 4
	},
	"second_heart": {
		"health": 1,
		"heal": 10,
		"duration": 5,
		"cooldown": 60
	},
	"bone_armor": {
		"divisor": 1.3
	},
	"hardened": {
		"physical": 17,
		"elemental": 25
	},
	"pain_block": {
		"threshold": 20,
		"percent": 40
	},
	"synapses": {
		"percent": 20
	},
	"neurostim": {
		"percent": 30
	},
	"reflex_arc": {
		"percent": 30,
		"duration": 5
	},
	"recycling": {
		"percent": 30
	},
	"assimilation": {
		"percent": 50
	},
	"battle_metabolism": {
		"percent": 5,
		"duration": 3,
		"maximum": 15
	},
	"killer_instinct": {
		"duration": 2,
		"multiplier": 2
	},
	"devourer": {
		"heal": 2,
		"absorption": 50,
		"duration": 5
	},
	"reactive_evolution": {
		"damage": 50,
		"percent": 30,
		"duration": 15
	},
	"retaliation": {
		"damage": 50,
		"window": 3,
		"radius": 6,
		"stun": 4,
		"cooldown": 15
	},
	"hyperactive": {
		"multiplier": 2,
		"percent": 20,
		"gap": 1,
		"cooldown": 10
	},
	"organic_ammo": {
		"health": 2,
		"threshold": 20,
		"cooldown": 5
	},
	"blood_burst": {
		"damage": 20,
		"radius": 2.4,
		"push": 0,
		"stun": 1
	},
	"discharge": {
		"hits": 6,
		"damage": 10,
		"range": 8,
		"chain": 3,
		"stun": 1.2
	},
	"power_strike": {
		"damage": 30,
		"reach": 3,
		"push": 4,
		"stun": 1.5,
		"width_start": 1,
		"width_end": 3
	},
	"active_claws": {
		"duration": 2.5,
		"radius": 3,
		"damage": 50
	},
	"blood_burst_2": {
		"damage": 30,
		"radius": 2.4,
		"push": 3,
		"stun": 1
	},
	"discharge_2": {
		"hits": 8,
		"damage": 20,
		"range": 8,
		"chain": 3,
		"stun": 1.2
	},
	"power_strike_2": {
		"damage": 40,
		"reach": 3,
		"push": 5,
		"stun": 1.5,
		"width_start": 1,
		"width_end": 3
	},
	"active_claws_2": {
		"duration": 3.5,
		"radius": 4,
		"damage": 60
	},
	"blood_burst_3": {
		"damage": 50,
		"radius": 2.4,
		"push": 4,
		"stun": 1
	},
	"discharge_3": {
		"hits": 10,
		"damage": 30,
		"range": 8,
		"chain": 3,
		"stun": 1.2
	},
	"power_strike_3": {
		"damage": 50,
		"reach": 3,
		"push": 5,
		"stun": 1.5,
		"width_start": 1,
		"width_end": 3
	},
	"active_claws_3": {
		"duration": 4.5,
		"radius": 5,
		"damage": 70
	},
	"blood_infection": {
		"damage": 30,
		"radius": 2.4,
		"push": 3,
		"dps": 10,
		"duration": 3,
		"explosion": 40,
		"explosion_radius": 4
	},
	"storm_pulse": {
		"duration": 6,
		"radius": 4,
		"damage": 40,
		"interval": 1,
		"stun": 2
	},
	"predator_dash": {
		"distance": 6,
		"damage": 50,
		"push": 2
	},
	"berserk": {
		"duration": 6,
		"percent": 50,
		"reduction": 33,
		"extension": 1,
		"maximum": 12
	}
}

static func value(id: String, key: String) -> float:
	return float(VALUES[id][key])

static func text_values(id: String, locale: String) -> Dictionary:
	var result := {}
	for key in VALUES.get(id, {}):
		var number := str(VALUES[id][key])
		result[key] = number.replace(".", ",") if locale.begins_with("ru") else number
	if id == "bone_armor":
		result["percent"] = str(roundi((1.0 - 1.0 / value(id, "divisor")) * 100.0))
	return result
