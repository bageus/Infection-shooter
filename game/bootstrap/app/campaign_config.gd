extends RefCounted
## Which levels and mode each platform build offers. Level names are map names in the level chain.

const VERSION := 1
const PATH := "res://game/bootstrap/app/campaign_config.json"
const MODES: Array[String] = ["campaign", "endless"]
const FALLBACK := "desktop"

var platforms: Dictionary = {}


func load_file(path: String = PATH) -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("version", 0)) != VERSION or not data.get("platforms") is Dictionary:
		return false
	platforms.clear()
	for key in data.platforms:
		var raw: Variant = data.platforms[key]
		if not raw is Dictionary or str(raw.get("mode", "")) not in MODES or not raw.get("levels") is Array:
			continue
		var names: Array[String] = []
		for item in raw.levels:
			names.append(str(item))
		platforms[str(key)] = {"mode": str(raw.mode), "levels": names}
	return platforms.has(FALLBACK)


func _entry(platform_id: String) -> Dictionary:
	return platforms.get(platform_id, platforms.get(FALLBACK, {"mode": "campaign", "levels": []}))


func mode(platform_id: String) -> String:
	return _entry(platform_id).mode


func levels(platform_id: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(_entry(platform_id).levels)
	return result
