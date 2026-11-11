extends RefCounted
## Light of each lamp model in play. "at" is in model space; the desk lamp's is under its shade.
## A "dir" lamp aims a spotlight along that direction; its range and cone angle are set per instance.

const BUDGET_LIGHT := preload("res://game/presentation/office_floor/budget_omni_light.gd")
const BUDGET_SPOT := preload("res://game/presentation/office_floor/budget_spot_light.gd")
const RANGE_LIMITS := Vector2(1.0, 12.0)
const ANGLE_LIMITS := Vector2(10.0, 80.0)

const SPECS := {
	"05_lamp.glb": {"at": Vector3(0.0, 0.12, 0.0), "color": Color(1.0, 0.86, 0.62), "energy": 1.1, "range": 2.8},
	"05_operating_lamp.glb": {"at": Vector3(0.64, 1.79, 0.2), "dir": Vector3(0.0, -0.6, 1.0), "color": Color(0.9, 0.96, 1.0), "energy": 1.6, "range": 4.0, "angle": 50.0},
	"05_construction_floodlight.glb": {"at": Vector3(0.0, 1.63, 0.2), "dir": Vector3(0.0, -0.4, 1.0), "color": Color(1.0, 0.94, 0.8), "energy": 2.2, "range": 6.0, "angle": 35.0},
}


## Range and angle the planner chose for a directional lamp; empty for other lamps.
static func shape(file: String, given: Dictionary) -> Dictionary:
	var spec: Dictionary = SPECS.get(file, {})
	if not spec.has("dir"):
		return {}
	return {"range": clampf(float(given.get("range", spec["range"])), RANGE_LIMITS.x, RANGE_LIMITS.y), "angle": clampf(float(given.get("angle", spec["angle"])), ANGLE_LIMITS.x, ANGLE_LIMITS.y)}


static func create(file: String, given: Dictionary) -> Node3D:
	var spec: Dictionary = SPECS[file]
	if not spec.has("dir"):
		var omni := BUDGET_LIGHT.create(spec["color"], spec["energy"], spec["range"])
		omni.position = spec["at"]
		return omni
	var values := shape(file, given)
	return BUDGET_SPOT.create(spec["color"], spec["energy"], values["range"], values["angle"], Transform3D(Basis.looking_at(spec["dir"]), spec["at"]))


static func apply(glow: Node, shape_values: Dictionary) -> void:
	if glow is SpotLight3D and not shape_values.is_empty():
		glow.spot_range = shape_values["range"]
		glow.spot_angle = shape_values["angle"]
