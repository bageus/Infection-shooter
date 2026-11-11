extends RefCounted
## Light of each lamp model in play. "at" is in model space; the desk lamp's is under its shade.

const SPECS := {
	"05_lamp.glb": {"at": Vector3(0.0, 0.12, 0.0), "color": Color(1.0, 0.86, 0.62), "energy": 1.1, "range": 2.8},
	"05_operating_lamp.glb": {"at": Vector3(0.64, 1.79, 0.2), "color": Color(0.9, 0.96, 1.0), "energy": 1.6, "range": 4.0},
	"05_construction_floodlight.glb": {"at": Vector3(0.0, 1.63, 0.2), "color": Color(1.0, 0.94, 0.8), "energy": 2.2, "range": 5.0},
}
