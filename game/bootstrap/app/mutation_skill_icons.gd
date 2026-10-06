extends RefCounted

# Skill icons cut from the 6x6 white atlas. Cell order follows
# assets/interface/icon/skill_icons_positions.txt (left to right, top to bottom).

const ATLAS := preload("res://assets/interface/icon/Clean white 6×6 icon atlas-1.png")
const GRID := 6
# Cell 23 (organic ammo) has no skill yet.
const CELLS := {
	"muscle_memory": 0, "stabilizers": 1, "combat_reflex": 2,
	"claws": 3, "blood_scent": 4, "adrenaline": 5,
	"hypertrophy": 6, "regeneration": 7, "second_heart": 8,
	"bone_armor": 9, "hardened": 10, "pain_block": 11,
	"synapses": 12, "neurostim": 13, "reflex_arc": 14,
	"recycling": 15, "assimilation": 16, "battle_metabolism": 17,
	"killer_instinct": 18, "devourer": 19, "reactive_evolution": 20,
	"retaliation": 21, "hyperactive": 22,
	"blood_burst": 24, "parasite": 25, "living_harvest": 26,
	"discharge": 27, "overload": 28, "storm_pulse": 29,
	"acid_spit": 30, "spore_cocoon": 31, "epidemic": 32,
	"predator_dash": 33, "bone_blades": 34, "berserk": 35
}

static var _cache: Dictionary = {}


static func for_skill(skill_id: String) -> Texture2D:
	if not CELLS.has(skill_id):
		return null
	if not _cache.has(skill_id):
		var cell := int(CELLS[skill_id])
		var size := ATLAS.get_size() / GRID
		var icon := AtlasTexture.new()
		icon.atlas = ATLAS
		icon.region = Rect2(Vector2(cell % GRID, floori(float(cell) / GRID)) * size, size)
		_cache[skill_id] = icon
	return _cache[skill_id]
