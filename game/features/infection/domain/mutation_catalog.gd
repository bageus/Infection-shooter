extends RefCounted

# One entry per circle. The column orders the tree from left to right.
const PASSIVE := [
	["muscle_memory", "Muscle Memory", "Arsenal", 0, "◉", "Reload weapons faster."],
	["stabilizers", "Stabilizers", "Arsenal", 1, "◎", "Reduce weapon spread."],
	["combat_reflex", "Combat Reflex", "Arsenal", 2, "✦", "Kills briefly increase fire rate."],
	["claws", "Claws", "Predator", 0, "✣", "Deal more melee damage."],
	["blood_scent", "Blood Scent", "Predator", 1, "◈", "Deal more damage to wounded enemies."],
	["adrenaline", "Adrenaline Rush", "Predator", 2, "⚡", "Nearby kills increase movement speed."],
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
	["killer_instinct", "Killer Instinct", "Arsenal + Predator", 3, "★", "Melee kills refill the magazine."],
	["devourer", "Devourer", "Predator + Biomass", 3, "✚", "Melee kills restore health."],
	["reactive_evolution", "Reactive Evolution", "Biomass + Adaptation", 3, "⬡", "Taking damage builds resistance."],
	["retaliation", "Retaliation", "Adaptation + Neural System", 3, "⚡", "Taking damage releases an electric pulse."],
	["hyperactive", "Hyperactive Organism", "Neural System + Metabolism", 3, "↯", "Kill streaks reduce ability cooldowns."]
]

const ACTIVE := [
	["blood_burst", "Blood Burst", "Biomass", 0, "✹", "Damage and knock back nearby enemies."],
	["parasite", "Parasite", "Biomass", 1, "✿", "Infect a target; its death spreads infection."],
	["living_harvest", "Living Harvest", "Biomass", 2, "♥", "Kills restore health and armor."],
	["discharge", "Discharge", "Neural Storm", 0, "⚡", "Chain lightning between enemies."],
	["overload", "Overload", "Neural Storm", 1, "↗", "Move, fire and reload faster."],
	["storm_pulse", "Storm Pulse", "Neural Storm", 2, "↯", "Stun enemies in an electric field."],
	["acid_spit", "Acid Spit", "Toxic Mutation", 0, "●", "Leave a corrosive acid pool."],
	["spore_cocoon", "Spore Cocoon", "Toxic Mutation", 1, "◌", "Release a delayed poisonous explosion."],
	["epidemic", "Epidemic", "Toxic Mutation", 2, "☣", "Spread infection to nearby enemies."],
	["predator_dash", "Predator Dash", "Predator Form", 0, "➤", "Damage enemies in your path."],
	["bone_blades", "Bone Blades", "Predator Form", 1, "✣", "Deal heavy damage at close range."],
	["berserk", "Berserk", "Predator Form", 2, "★", "Kills boost speed, damage and defense."]
]

const HYBRID_PARENTS := {
	"killer_instinct": ["combat_reflex", "adrenaline"],
	"devourer": ["adrenaline", "second_heart"],
	"reactive_evolution": ["second_heart", "pain_block"],
	"retaliation": ["pain_block", "reflex_arc"],
	"hyperactive": ["reflex_arc", "battle_metabolism"]
}


# Hybrids are derived bonuses from the last circles of adjacent full branches.
const PASSIVE_STAGES := {
	"Arsenal": 0, "Predator": 1, "Biomass": 2,
	"Adaptation": 3, "Neural System": 4, "Metabolism": 4
}
const ACTIVE_STAGES := {
	"Toxic Mutation": 0, "Biomass": 1, "Predator Form": 2, "Neural Storm": 3
}
const FIRST_POINT := 25.0
const POINT_STEP := 5.0
const STABILITY_STAGES := [30.0, 45.0, 60.0, 75.0, 90.0]


static func all() -> Array:
	return ACTIVE + PASSIVE


static func find(skill_id: String) -> Array:
	for row in all():
		if str(row[0]) == skill_id:
			return row
	return []


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


static func threshold(row: Array) -> float:
	if int(row[3]) == 3:
		return FIRST_POINT + float(stage(row)) * 15.0 + 10.0
	return FIRST_POINT + float(stage(row)) * 15.0 + float(row[3]) * POINT_STEP
