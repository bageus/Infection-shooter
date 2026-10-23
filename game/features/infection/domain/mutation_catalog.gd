extends RefCounted

# One entry per circle. The column orders the tree from left to right.
const PASSIVE := [
	["muscle_memory", "Muscle Memory", "Arsenal", 0, "◉", "Reload time is reduced by {percent}%."],
	["stabilizers", "Stabilizers", "Arsenal", 1, "◎", "Weapon spread is reduced by {percent}% for more accurate shots."],
	["combat_reflex", "Combat Reflex", "Arsenal", 2, "✦", "Kills increase fire rate by {percent}% for {duration}s."],
	["claws", "Claws", "Predator", 0, "✣", "Automatically deal {damage} damage to nearby enemies every {interval}s."],
	["blood_scent", "Blood Scent", "Predator", 1, "◈", "Deal {percent}% more damage to wounded enemies."],
	["adrenaline", "Adrenaline Rush", "Predator", 2, "⚡", "Kills made by passive Claws increase movement speed by {percent}% for {duration}s."],
	["hypertrophy", "Hypertrophy", "Biomass", 0, "✚", "Maximum health increases by {percent}%."],
	["regeneration", "Regeneration", "Biomass", 1, "✿", "Recover {heal} health per second after {delay}s without taking damage."],
	["second_heart", "Second Heart", "Biomass", 2, "♥", "A lethal hit leaves you at {health} health. Recover {heal} health per second for {duration}s. Recovery: {cooldown}s."],
	["bone_armor", "Bone Armor", "Adaptation", 0, "⬡", "Take {percent}% less physical damage."],
	["hardened", "Hardened Tissue", "Adaptation", 1, "◇", "Take {physical}% less physical damage and {elemental}% less fire, acid and electric damage."],
	["pain_block", "Pain Block", "Adaptation", 2, "◆", "Below {threshold}% health, take {percent}% less damage."],
	["synapses", "Accelerated Synapses", "Neural System", 0, "↗", "Move {percent}% faster."],
	["neurostim", "Neurostimulation", "Neural System", 1, "↻", "Active skill recovery time is reduced by {percent}%."],
	["reflex_arc", "Reflex Arc", "Neural System", 2, "➤", "After a roll, fire {percent}% faster for {duration}s."],
	["recycling", "Recycling", "Metabolism", 0, "▣", "Enemies drop ammunition {percent}% more often."],
	["assimilation", "Assimilation", "Metabolism", 1, "◉", "Medkits and other consumables are {percent}% more effective."],
	["battle_metabolism", "Battle Metabolism", "Metabolism", 2, "✹", "Each kill grants +{percent}% damage for {duration}s. Further kills add {duration}s to the remaining time and increase the bonus up to +{maximum}%."],
	["killer_instinct", "Killer Instinct", "Arsenal + Predator", 3, "★", "Every kill refills your magazine from reserves and doubles weapon damage for {duration}s."],
	["devourer", "Devourer", "Predator + Biomass", 3, "✚", "Mutagen clouds restore {heal} health per second. At full health, gain separate protection absorbing up to {absorption} damage for {duration}s."],
	["reactive_evolution", "Reactive Evolution", "Biomass + Adaptation", 3, "⬡", "After taking a total of {damage} physical damage, gain {percent}% physical resistance for {duration}s."],
	["retaliation", "Retaliation", "Adaptation + Neural System", 3, "⚡", "Take {damage} damage within {window}s to stun enemies within {radius}m for {stun}s. Recovery: {cooldown}s."],
	["hyperactive", "Hyperactive Organism", "Neural System + Metabolism", 3, "↯", "A kill doubles active skill recovery speed and increases movement speed by {percent}%. Keep killing with gaps no longer than {gap}s to maintain it. When the streak ends, recovery: {cooldown}s."],
	["organic_ammo", "Organic Ammo", "Metabolism + Arsenal", 3, "▣", "An empty magazine automatically refills for {health} health. Free below {threshold}% health. Recovery: {cooldown}s."]
]

const ACTIVE := [
	["blood_burst", "Blood Burst", "Biomass", 0, "✹", "Deal {damage} damage to enemies within {radius}m."],
	["blood_burst_2", "Blood Burst 2", "Biomass", 1, "✹", "Deal {damage} damage within {radius}m and push enemies {push}m beyond the area."],
	["blood_burst_3", "Blood Burst 3", "Biomass", 2, "✹", "Deal {damage} damage within {radius}m, push enemies {push}m beyond the area and stun them for {stun}s."],
	["blood_infection", "Infectious Burst", "Biomass", 2, "✹", "Deal {damage} damage within {radius}m and push enemies {push}m beyond the area. Infection deals {dps} damage/s for {duration}s; only deaths from infection explode for {explosion} damage within {explosion_radius}m."],
	["discharge", "Discharge", "Neural Storm", 0, "⚡", "Lightning hits up to {hits} times for {damage} damage each. First target within {range}m; jumps up to {chain}m."],
	["discharge_2", "Discharge 2", "Neural Storm", 1, "⚡", "Lightning hits up to {hits} times for {damage} damage each. First target within {range}m; jumps up to {chain}m."],
	["discharge_3", "Discharge 3", "Neural Storm", 2, "⚡", "Lightning hits up to {hits} times for {damage} damage each, stunning for {stun}s. First target within {range}m; jumps up to {chain}m."],
	["storm_pulse", "Storm Pulse", "Neural Storm", 2, "⚡", "For {duration}s, surround yourself with an electric field of {radius}m. Deal {damage} damage/s and refresh a {stun}s stun every second."],
	["power_strike", "Power Strike", "Might", 0, "➤", "Strike ahead for {damage} damage up to {reach}m away and push enemies {push}m."],
	["power_strike_2", "Power Strike 2", "Might", 1, "➤", "Strike ahead for {damage} damage up to {reach}m away and push enemies {push}m."],
	["power_strike_3", "Power Strike 3", "Might", 2, "➤", "Strike ahead for {damage} damage up to {reach}m away, push enemies {push}m and stun for {stun}s."],
	["predator_dash", "Dash", "Might", 2, "➤", "Dash forward {distance}m, dealing {damage} damage once per enemy and pushing them {push}m sideways. Obstacles stop the dash."],
	["active_claws", "Claws", "Predator Form", 0, "✣", "For {duration}s, surround yourself with claws: enemies within {radius}m take {damage} damage per second."],
	["active_claws_2", "Claws 2", "Predator Form", 1, "✣", "For {duration}s, surround yourself with claws: enemies within {radius}m take {damage} damage per second."],
	["active_claws_3", "Claws 3", "Predator Form", 2, "✣", "For {duration}s, surround yourself with claws: enemies within {radius}m take {damage} damage per second."],
	["berserk", "Berserk", "Predator Form", 2, "✣", "For {duration}s, increase movement speed and weapon damage by {percent}% and take {reduction}% less damage. Kills add {extension}s, up to {maximum}s remaining."]
]

const HYBRID_PARENTS := {
	"killer_instinct": ["combat_reflex", "adrenaline"],
	"devourer": ["adrenaline", "second_heart"],
	"reactive_evolution": ["second_heart", "pain_block"],
	"retaliation": ["pain_block", "reflex_arc"],
	"hyperactive": ["reflex_arc", "battle_metabolism"],
	"organic_ammo": ["battle_metabolism", "combat_reflex"]
}


# Rank determines recovery after the effect finishes.
const DEFAULT_COOLDOWN := 5.0
const ACTIVE_BRANCHES := ["Biomass", "Neural Storm", "Might", "Predator Form"]
const ALTERNATIVES := ["blood_infection", "storm_pulse", "predator_dash", "berserk"]

static func is_active_skill(skill_id: String) -> bool:
	return find(skill_id) in ACTIVE

static func family(skill_id: String) -> String:
	var row := find(skill_id)
	return str(row[2]) if row in ACTIVE else ""

static func level(skill_id: String) -> int:
	var row := find(skill_id)
	return int(row[3]) + 1 if row in ACTIVE else 0

static func alternative(skill_id: String) -> bool:
	return skill_id in ALTERNATIVES

# Hybrids are derived bonuses from the last circles of adjacent full branches.
const PASSIVE_STAGES := {
	"Arsenal": 0, "Predator": 1, "Biomass": 2,
	"Adaptation": 3, "Neural System": 4, "Metabolism": 4
}
const ACTIVE_STAGES := {
	"Might": 0, "Biomass": 1, "Predator Form": 2, "Neural Storm": 3
}
const FIRST_POINT := 25.0
const POINT_STEP := 5.0
const STABILITY_STAGES := [30.0, 45.0, 60.0, 75.0, 90.0]


static var _all: Array = []
static var _by_id: Dictionary = {}


# Built once: these lookups run several times per frame (skill effects).
static func all() -> Array:
	if _all.is_empty():
		_all = ACTIVE + PASSIVE
	return _all


static func find(skill_id: String) -> Array:
	if _by_id.is_empty():
		for row in all():
			_by_id[str(row[0])] = row
	return _by_id.get(skill_id, [])


static func cooldown(skill_id: String) -> float:
	var rank := level(skill_id)
	return [5.0, 6.0, 8.0][rank - 1] if rank > 0 else DEFAULT_COOLDOWN


static func point_budget(mutation: float) -> int:
	return maxi(0, floori((clampf(mutation, 0.0, 100.0) - FIRST_POINT) / POINT_STEP) + 1)


static func stage(row: Array) -> int:
	if int(row[3]) == 3:
		var latest := 0
		for parent_id in HYBRID_PARENTS[str(row[0])]:
			latest = maxi(latest, stage(find(str(parent_id))))
		return latest
	var stages: Dictionary = ACTIVE_STAGES if row in ACTIVE else PASSIVE_STAGES
	return int(stages[str(row[2])])


static func required_stability(row: Array) -> float:
	return float(STABILITY_STAGES[stage(row)])


# The critical threshold tops out at 95 and mutation above it means control
# loss, so a 95 requirement could only be met at exactly 95.0. The last circle
# opens one point earlier to leave a playable window.
const HIGHEST_REACHABLE_THRESHOLD := 94.0


static func threshold(row: Array) -> float:
	var value := FIRST_POINT + float(stage(row)) * 15.0 + (10.0 if int(row[3]) == 3 else float(row[3]) * POINT_STEP)
	return minf(value, HIGHEST_REACHABLE_THRESHOLD)
