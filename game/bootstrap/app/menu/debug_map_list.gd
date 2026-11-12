extends RefCounted
## Debug main-menu map rows: the player's saved planner maps first, then the shipped ones.

const STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const CAMPAIGN := preload("res://game/bootstrap/app/campaign_config.gd")
const PLATFORM := preload("res://game/infrastructure/platform/public/platform.gd")


## Rows of {"label", "path", "shipped"}; a path is only listed when its file exists.
static func entries() -> Array:
	var rows: Array = []
	var dir := DirAccess.open(STORAGE.MAPS_DIR)
	if dir != null:
		var names := dir.get_files()
		names.sort()
		for file_name in names:
			if file_name.to_lower().ends_with(".json"):
				rows.append({"label": file_name.get_basename(), "path": STORAGE.MAPS_DIR + "/" + file_name, "shipped": false})
	var campaign := CAMPAIGN.new()
	campaign.load_file()
	var shipped: Array[String] = []
	shipped.append_array(campaign.map_paths(PLATFORM.detect_id()))
	for path in shipped:
		if FileAccess.file_exists(path):
			rows.append({"label": path.get_file().get_basename(), "path": path, "shipped": true})
	return rows
