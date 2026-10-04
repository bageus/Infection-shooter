extends RefCounted
## Layouts of the supplied effect sprite sheets. Frames run left to right,
## top to bottom; `durations` is the time each frame stays on screen.

const ROOT := "res://models/objects/textures/"

# 12 frames: the flash plays fast, the closing smoke frames slowly.
const GRENADE_EXPLOSION := {
	"path": ROOT + "grenade_explosion_layers/grenade_explosion_atlas.png",
	"columns": 4, "rows": 3, "frames": 12,
	"durations": [0.03, 0.03, 0.035, 0.04, 0.05, 0.06, 0.08, 0.11, 0.15, 0.21, 0.29, 0.4],
}

# Six-frame electrical spark burst.
const ELECTRIC_SPARK := {
	"path": ROOT + "electric_spark_burst.png",
	"columns": 3, "rows": 2, "frames": 6,
	"durations": [0.03, 0.035, 0.035, 0.04, 0.045, 0.055],
}

# Ten torn paper scraps; each sprite shows one fixed frame.
const TORN_PAPER := {
	"path": ROOT + "torn_paper_debris.png",
	"columns": 5, "rows": 2, "frames": 10,
	"durations": [],
}

# Fire extinguisher discharge and rupture.
const EXTINGUISHER_SPRAY := {
	"path": ROOT + "fire_extinguisher_layers/fire_extinguisher_atlas.png",
	"columns": 4, "rows": 3, "frames": 12,
	"durations": [0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.1, 0.12, 0.14, 0.17, 0.21, 0.27],
}


static func available(atlas: Dictionary) -> bool:
	return not atlas.is_empty() and ResourceLoader.exists(str(atlas.get("path", "")))
