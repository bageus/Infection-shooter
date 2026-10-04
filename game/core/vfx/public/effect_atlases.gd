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


static func available(atlas: Dictionary) -> bool:
	return not atlas.is_empty() and ResourceLoader.exists(str(atlas.get("path", "")))
