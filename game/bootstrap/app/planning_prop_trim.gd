extends RefCounted
## Effects quality drops small decor when a mission loads, so weak machines draw fewer objects.
## Low drops models up to 0.5 m, Medium up to 0.25 m, High keeps everything. Dropped records stay in the
## map's preserved records, so saving from the planner still writes them.
const EFFECTS_QUALITY := preload("res://game/core/vfx/public/effects_quality.gd")
const SIZES_PATH := "res://game/bootstrap/app/prop_sizes.json"
const MAX_SIZE_BY_LEVEL := [0.5, 0.25, 0.0]
const ENVIRONMENT_DIR := "/models/objects/enviroments/"
static var _sizes: Dictionary = {}


## True when this record's model is small decor for the current effects quality.
## Records with an object id (quest targets, hosts) and desk items always stay.
static func drops(record: Dictionary, scene_path: String, planner_active: bool) -> bool:
	var limit: float = MAX_SIZE_BY_LEVEL[clampi(EFFECTS_QUALITY.level, 0, MAX_SIZE_BY_LEVEL.size() - 1)]
	if limit <= 0.0 or planner_active or not scene_path.contains(ENVIRONMENT_DIR) or not scene_path.ends_with(".glb"):
		return false
	if not str(record.get("object_id", "")).is_empty() or not str(record.get("desk_id", "")).is_empty():
		return false
	var size: float = float(_table().get(scene_path.get_file(), INF))
	var scale := maxf(absf(float(record.get("scale_x", 1.0))), maxf(absf(float(record.get("scale_y", 1.0))), absf(float(record.get("scale_z", 1.0)))))
	return size * scale <= limit


static func _table() -> Dictionary:
	if _sizes.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SIZES_PATH))
		_sizes = parsed if parsed is Dictionary else {}
	return _sizes
