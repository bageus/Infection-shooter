extends RefCounted

# One entry per circle. The column orders the tree from left to right.
const PASSIVE := [
	["muscle_memory", "Muscle Memory", "Arsenal", 0, "◉", "Reload weapons faster."],
	["stabilizers", "Stabilizers", "Arsenal", 1, "◎", "Reduce weapon spread."],
	["combat_reflex", "Combat Reflex", "Arsenal", 2, "✦", "Kills briefly increase fire rate."],
	["claws", "Claws", "Predator", 0, "✣", "Pulse damage to nearby enemies every 3 seconds."],
	["blood_scent", "Blood Scent", "Predator", 1, "◈", "Deal more damage to wounded enemies."],
	["adrenaline", "Adrenaline Rush", "Predator", 2, "⚡", "Kills made by Claws boost movement speed."],
	["hypertrophy", "Hypertrophy", "Biomass", 0, "✚", "Increase maximum health."],
	["regeneration", "Regeneration", "Biomass", 1, "✿", "Regain health over time."],
	["second_heart", "Second Heart", "Biomass", 2, "♥", "Survive a lethal hit."],
	["bone_armor", "Bone Armor", "Adaptation", 0, "⬡", "Take less physical damage."],
	["hardened", "Hardened Tissue", "Adaptation", 1, "◇", "Resist elemental damage."],
	["pain_block", "Pain Block", "Adaptation", 2, "◆", "Gain protection at low health."],
	["synapses", "Accelerated Synapses", "Neural System", 0, "↗", "Move faster."],
	["neurostim", "Neurostimulation", "Neural System", 1, "↻", "Reduce ability cooldowns."],
	["reflex_arc", "Reflex Arc", "Neural System", 2, "➤", "Fire faster after rolling."],
	["recycling", "Recycling", "Metabolism", 0, "▣", "Get more ammo from enemies."],
	["assimilation", "Assimilation", "Metabolism", 1, "◉", "Heal more effectively."],
	["battle_metabolism", "Battle Metabolism", "Metabolism", 2, "✹", "Kills increase your damage."],
	["killer_instinct", "Killer Instinct", "Arsenal + Predator", 3, "★", "Melee kills refill the magazine and double damage."],
	["devourer", "Devourer", "Predator + Biomass", 3, "✚", "Kills leave a healing mutagen cloud; full health grants armour."],
	["reactive_evolution", "Reactive Evolution", "Biomass + Adaptation", 3, "⬡", "Repeated damage of one type builds a block against it."],
	["retaliation", "Retaliation", "Adaptation + Neural System", 3, "⚡", "Taking damage releases an electric pulse."],
	["hyperactive", "Hyperactive Organism", "Neural System + Metabolism", 3, "↯", "Kill streaks speed up ability recovery."]
]

const ACTIVE := [
	["blood_burst", "Blood Burst", "Biomass", 0, "✹", ""],
	["blood_burst_2", "Blood Burst 2", "Biomass", 1, "✹", ""],
	["blood_burst_3", "Blood Burst 3", "Biomass", 2, "✹", ""],
	["blood_infection", "Infectious Burst", "Biomass", 2, "✹", ""],
	["discharge", "Discharge", "Neural Storm", 0, "⚡", ""],
	["discharge_2", "Discharge 2", "Neural Storm", 1, "⚡", ""],
	["discharge_3", "Discharge 3", "Neural Storm", 2, "⚡", ""],
	["storm_pulse", "Storm Pulse", "Neural Storm", 2, "⚡", ""],
	["power_strike", "Power Strike", "Might", 0, "➤", ""],
	["power_strike_2", "Power Strike 2", "Might", 1, "➤", ""],
	["power_strike_3", "Power Strike 3", "Might", 2, "➤", ""],
	["predator_dash", "Dash", "Might", 2, "➤", ""],
	["active_claws", "Claws", "Predator Form", 0, "✣", ""],
	["active_claws_2", "Claws 2", "Predator Form", 1, "✣", ""],
	["active_claws_3", "Claws 3", "Predator Form", 2, "✣", ""],
	["berserk", "Berserk", "Predator Form", 2, "✣", ""]
]

const HYBRID_PARENTS := {
	"killer_instinct": ["combat_reflex", "adrenaline"],
	"devourer": ["adrenaline", "second_heart"],
	"reactive_evolution": ["second_heart", "pain_block"],
	"retaliation": ["pain_block", "reflex_arc"],
	"hyperactive": ["reflex_arc", "battle_metabolism"]
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
