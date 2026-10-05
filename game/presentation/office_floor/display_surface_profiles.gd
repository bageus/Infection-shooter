extends RefCounted

const MODELS: Array[String] = [
	"05_monitor_destructible.glb", "05_monitor_wide_destructible.glb", "05_monitor2_destructible.glb",
	"05_monitor3_server_destructible.glb", "05_monitor4_server_destructible.glb",
	"05_laptop_destructible.glb", "05_laptop2_destructible.glb",
	"05_wall_TV_destructible.glb", "05_wall_TV_frameless_destructible.glb"]
const DATA_PATH := "res://game/presentation/office_floor/display_surfaces.json"
var profiles: Dictionary


func _init() -> void:
	profiles = (JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) as Dictionary)["profiles"]


func contains(path: String) -> bool:
	return path.get_file() in MODELS


func screens(path: String) -> Array:
	return (profiles.get(path.get_file(), {}) as Dictionary).get("screens", [])


static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
