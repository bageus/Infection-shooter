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
	["hyperactive", "Hyperactive Organism", "Neural System + Metabolism", 3, "↯", "Kill streaks reduce ability cooldowns."],
	["organic_ammo", "Organic Ammo", "Metabolism + Arsenal", 3, "❖", "Convert health into ammunition."]
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
	"killer_instinct": ["muscle_memory", "claws"],
	"devourer": ["claws", "hypertrophy"],
	"reactive_evolution": ["hypertrophy", "bone_armor"],
	"retaliation": ["bone_armor", "synapses"],
	"hyperactive": ["synapses", "recycling"],
	"organic_ammo": ["recycling", "muscle_memory"]
}


static func all() -> Array:
	return ACTIVE + PASSIVE


static func find(skill_id: String) -> Array:
	for row in all():
		if str(row[0]) == skill_id:
			return row
	return []


static func threshold(row: Array) -> float:
	return 25.0 + float(row[3]) * 15.0
