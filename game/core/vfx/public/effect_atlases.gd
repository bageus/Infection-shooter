extends RefCounted
## Layouts of the supplied effect sprite sheets. Frames run left to right,
## top to bottom; `durations` is the time each frame stays on screen.
## `pivot` is the frame point (UV, y down) that sits on the effect origin.

const ROOT := "res://models/objects/textures/"

# 12 frames, 4x3: flash, fireball with a ground ring, then rolling smoke.
# The flash plays fast, the closing smoke frames slowly.
const GRENADE_EXPLOSION := {
	"path": ROOT + "grenade_explosion_layers/Twelve-frame fiery explosion flipbook atlas.png",
	"columns": 4, "rows": 3, "frames": 12,
	"durations": [0.03, 0.03, 0.035, 0.04, 0.05, 0.06, 0.08, 0.11, 0.15, 0.21, 0.29, 0.4],
	"pivot": Vector2(0.5, 0.93),
	"edge_softness": 0.14,
}

# Six-frame electrical spark burst, 3x2.
const ELECTRIC_SPARK := {
	"path": ROOT + "flick/Six-frame electrical spark burst sprite sheet.png",
	"columns": 3, "rows": 2, "frames": 6,
	"durations": [0.03, 0.035, 0.035, 0.04, 0.045, 0.055],
	"pivot": Vector2(0.5, 0.5),
}

# Ten torn paper scraps, 5x2; each sprite shows one fixed frame.
const TORN_PAPER := {
	"path": ROOT + "paper/Ten torn paper debris sprites.png",
	"columns": 5, "rows": 2, "frames": 10,
	"durations": [],
	"pivot": Vector2(0.5, 0.5),
}

# Fire extinguisher, 4x3: frames 0-5 the powder jet growing out of the nozzle
# (bottom left, aimed up and to the right), 6-11 the rupture cloud dispersing.
const EXTINGUISHER_SPRAY := {
	"path": ROOT + "fire_extinguisher_layers/Fire extinguisher powder burst atlas.png",
	"columns": 4, "rows": 3, "frames": 12,
	"durations": [0.05, 0.05, 0.06, 0.07, 0.08, 0.09, 0.05, 0.06, 0.09, 0.13, 0.2, 0.3],
	"pivot": Vector2(0.12, 0.89),
	"edge_softness": 0.08,
	"jet_angle": 0.71,
	"spray_frames": Vector2i(0, 5),
	"spray_loop_from": 3,
	"burst_frames": Vector2i(6, 11),
}


# --- Mutation skill sheets (fx_skills). Rings and spreads are drawn as seen
# from a low camera; they play flat on the floor (sprite_flipbook `ground`)
# with `ground_stretch` undoing the drawn ellipse. `extent` is the
# share of the frame width the effect's ring or spread covers: a radius R
# plays at size 2R / extent.
const SKILL_ROOT := ROOT + "fx_skills/"

# Storm Pulse field around the player: 8 variations of the same field, looped.
const ELECTRIC_FIELD := {
	"path": SKILL_ROOT + "Eight-Frame Isometric Electric Field.png",
	"columns": 4, "rows": 2, "frames": 8,
	"durations": [0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07, 0.07],
	"pivot": Vector2(0.5, 0.67),
	"extent": 0.9,
	"ground_stretch": 2.3,
}

# Claw strike: three slashes grow, flash and fade.
const CLAW_SLASH := {
	"path": SKILL_ROOT + "Eight-frame isometric mutant claw slash atlas.png",
	"columns": 4, "rows": 2, "frames": 8,
	"durations": [0.025, 0.025, 0.03, 0.035, 0.04, 0.05, 0.06, 0.08],
	"pivot": Vector2(0.55, 0.55),
}

# Stunning electric pulse: a spark opens into a lightning ring and fades.
const ELECTRIC_PULSE := {
	"path": SKILL_ROOT + "Eight-frame isometric electric pulse atlas.png",
	"columns": 4, "rows": 2, "frames": 8,
	"durations": [0.03, 0.035, 0.04, 0.045, 0.05, 0.06, 0.07, 0.09],
	"pivot": Vector2(0.5, 0.52),
	"extent": 0.9,
	"ground_stretch": 2.2,
}

# Blood Burst: spikes shoot out from the centre and thin away.
const SPIKE_BURST := {
	"path": SKILL_ROOT + "Oblique isometric spike burst atlas.png",
	"columns": 4, "rows": 2, "frames": 8,
	"durations": [0.03, 0.035, 0.04, 0.045, 0.06, 0.07, 0.08, 0.1],
	"pivot": Vector2(0.5, 0.58),
	"extent": 0.95,
	"ground_stretch": 2.2,
}

# Energy shield dome; frames 0-7 shimmer, so the dome can also hold a loop.
const ENERGY_SHIELD := {
	"path": SKILL_ROOT + "Eight-frame isometric energy shield atlas.png",
	"columns": 4, "rows": 2, "frames": 8,
	"durations": [0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05],
	"pivot": Vector2(0.5, 0.82),
	"extent": 0.84,
}

# Chain lightning grows from the start point (bottom left) to the far end
# (top right): played along each link with the sheet's own direction.
const CHAIN_LIGHTNING := {
	"path": SKILL_ROOT + "Isometric chain lightning VFX atlas.png",
	"columns": 4, "rows": 2, "frames": 8,
	"durations": [0.025, 0.03, 0.03, 0.035, 0.04, 0.045, 0.06, 0.08],
	"pivot": Vector2(0.13, 0.78),
	"jet_angle": 0.66,
	"reach": 0.88,
}

# Spore Cocoon, 4x3: frames 0-6 the cocoon swells (its fuse), 7 the rupture
# flash, 8-11 the spore cloud thinning out.
const SPORE_COCOON := {
	"path": SKILL_ROOT + "Mutant growth mutagen burst sprite atlas.png",
	"columns": 4, "rows": 3, "frames": 12,
	"durations": [0.3, 0.3, 0.3, 0.28, 0.28, 0.27, 0.27, 0.06, 0.12, 0.2, 0.3, 0.45],
	"pivot": Vector2(0.5, 0.9),
	"extent": 0.9,
	"fuse_frames": 7,
}

# Bone Blades orbit: one turn over 8 frames, looped while the buff lasts.
const BLADE_ORBIT := {
	"path": SKILL_ROOT + "Isometric cyan blade orbit atlas.png",
	"columns": 4, "rows": 2, "frames": 8,
	"durations": [0.06, 0.06, 0.06, 0.06, 0.06, 0.06, 0.06, 0.06],
	"pivot": Vector2(0.5, 0.55),
	"extent": 0.95,
	"ground_stretch": 1.6,
}

# Three gold stars on a ring, 4x2: loops over a stunned enemy's head.
const STUN_STARS := {
	"path": SKILL_ROOT + "Isometric golden stun star animation atlas.png",
	"columns": 4, "rows": 2, "frames": 8,
	"durations": [0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08],
	"pivot": Vector2(0.5, 0.5),
}

# Four acid puddle variants, 2x2 with 3:2 cells; one fixed frame per pool.
# A square quad squeezes the cell, so ground_stretch also undoes that.
const ACID_PUDDLES := {
	"path": SKILL_ROOT + "Four emerald acid puddles.png",
	"columns": 2, "rows": 2, "frames": 4,
	"durations": [],
	"pivot": Vector2(0.5, 0.5),
	"extent": 0.86,
	"ground_stretch": 1.17,
	"cell_aspect": 1.5,
}

# Anatomical heart, 3x2: six beat frames, looped.
const HEARTBEAT := {
	"path": SKILL_ROOT + "Cartoon anatomical heart heartbeat sprite sheet.png",
	"columns": 3, "rows": 2, "frames": 6,
	"durations": [0.09, 0.09, 0.09, 0.09, 0.09, 0.09],
	"pivot": Vector2(0.5, 0.5),
}

static func available(atlas: Dictionary) -> bool:
	return not atlas.is_empty() and ResourceLoader.exists(str(atlas.get("path", "")))


## Size of a quad whose drawn ring/spread spans `radius` metres.
static func size_for_radius(atlas: Dictionary, radius: float) -> float:
	return radius * 2.0 / maxf(float(atlas.get("extent", 1.0)), 0.05)
