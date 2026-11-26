extends RefCounted
## The web arenas: maps named arena_<theme>_<n> (shipped in content/levels or saved by the planner).
## A new run plays a random arena that is not beaten yet.

const PREFIX := "arena_"
const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
const CAMPAIGN := preload("res://game/bootstrap/app/campaign_config.gd")
const DIRS: Array[String] = [CAMPAIGN.MAPS_DIR, "user://maps"]


## Sorted unique arena map names found in `dirs`.
static func names(dirs: Array = DIRS) -> Array[String]:
	var found: Array[String] = []
	for folder: String in dirs:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file in DirAccess.get_files_at(folder):
			var map_name := file.get_basename()
			if file.get_extension() == "json" and map_name.begins_with(PREFIX) and map_name not in found:
				found.append(map_name)
	found.sort()
	return found


## Arenas not beaten yet.
static func remaining(dirs: Array = DIRS) -> Array[String]:
	var result: Array[String] = []
	for map_name in names(dirs):
		if not WALLET.is_beaten(map_name):
			result.append(map_name)
	return result


static func is_arena(map_name: String) -> bool:
	return map_name.begins_with(PREFIX)
