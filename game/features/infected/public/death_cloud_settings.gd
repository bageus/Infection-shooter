extends RefCounted
## Planner options of an infected's death mutagen cloud: whether one forms, when it
## ends by time (none, auto or a set duration) and/or after absorbing some mutagen.
## {"enabled": bool, "time": "none" | "auto" | "manual", "seconds": float, "absorb": bool, "units": float, "radius": float}

const TIME_MODES: Array[String] = ["none", "auto", "manual"]
const SECONDS_MIN := 2.0
const SECONDS_MAX := 60.0
const UNITS_MIN := 1.0
const UNITS_MAX := 100.0
const RADIUS_MIN := 0.5
const RADIUS_MAX := 4.0
const RADIUS_DEFAULT := 1.35


## Always returns a usable config; unknown modes and bad numbers fall back to the defaults.
static func sanitize(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var time := str(source.get("time", "auto"))
	if time not in TIME_MODES:
		time = "auto"
	var absorb := bool(source.get("absorb", false))
	# With no time limit and no absorption end, the cloud would never leave: keep it timed.
	if time == "none" and not absorb:
		time = "auto"
	return {
		"enabled": bool(source.get("enabled", true)),
		"time": time,
		"seconds": clampf(_number(source.get("seconds"), 14.0), SECONDS_MIN, SECONDS_MAX),
		"absorb": absorb,
		"units": clampf(_number(source.get("units"), 10.0), UNITS_MIN, UNITS_MAX),
		"radius": clampf(_number(source.get("radius"), RADIUS_DEFAULT), RADIUS_MIN, RADIUS_MAX),
	}


## Sets the lifecycle of a mutagen cloud. Auto keeps the cloud's own lifetime.
static func apply(cloud: Node, config: Dictionary) -> void:
	cloud.set("timed", config["time"] != "none")
	if config["time"] == "manual":
		cloud.set("lifetime_seconds", config["seconds"])
	cloud.set("ends_when_absorbed", config["absorb"])
	cloud.set("absorb_units", config["units"])
	cloud.set("cloud_radius", config["radius"])


static func _number(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) and is_finite(float(value)) else fallback
