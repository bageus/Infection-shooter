extends RefCounted
## Which levels and mode each platform build offers. Level names are map names in the level chain.

const VERSION := 1
const PATH := "res://game/bootstrap/app/campaign_config.json"
const MODES: Array[String] = ["campaign", "endless"]
const FALLBACK := "desktop"
## Shipped maps (and an optional level_chain.json) of a platform build live here, one <level>.json per level.
const MAPS_DIR := "res://content/levels/"

var platforms: Dictionary = {}
var steam_url := ""


func load_file(path: String = PATH) -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or int(data.get("version", 0)) != VERSION or not data.get("platforms") is Dictionary:
		return false
	platforms.clear()
	steam_url = str(data.get("steam_url", ""))
	for key in data.platforms:
		var raw: Variant = data.platforms[key]
		if not raw is Dictionary or str(raw.get("mode", "")) not in MODES or not raw.get("levels") is Array:
			continue
		var names: Array[String] = []
		for item in raw.levels:
			names.append(str(item))
		platforms[str(key)] = {"mode": str(raw.mode), "levels": names, "steam_promo": bool(raw.get("steam_promo", false)), "ads": bool(raw.get("ads", false))}
	return platforms.has(FALLBACK)


func _entry(platform_id: String) -> Dictionary:
	return platforms.get(platform_id, platforms.get(FALLBACK, {"mode": "campaign", "levels": []}))


func mode(platform_id: String) -> String:
	return _entry(platform_id).mode


func levels(platform_id: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(_entry(platform_id).levels)
	return result


## Where the shipped map of every level of the platform lives (the file may not exist yet).
func map_paths(platform_id: String) -> Array[String]:
	var result: Array[String] = []
	for level in levels(platform_id):
		result.append(MAPS_DIR + level + ".json")
	return result


## The level whose waves never end (the last one of an endless platform), else "".
func endless_level(platform_id: String) -> String:
	var names := levels(platform_id)
	return names[-1] if mode(platform_id) == "endless" and not names.is_empty() else ""


## Map of the first level when the platform ships one, else "" (the default map plays).
func first_shipped_map(platform_id: String) -> String:
	var paths := map_paths(platform_id)
	return paths[0] if not paths.is_empty() and FileAccess.file_exists(paths[0]) else ""


## Store page to promote on this platform's menus and loading screen, or "" when it shows no promo.
func steam_promo_url(platform_id: String) -> String:
	return steam_url if bool(_entry(platform_id).get("steam_promo", false)) else ""


## True when the platform shows a fullscreen advertisement before a restart.
func shows_ads(platform_id: String) -> bool:
	return bool(_entry(platform_id).get("ads", false))
