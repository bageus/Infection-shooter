extends RefCounted

# Wall-mounted environment GLBs; structural walls and freestanding boards are excluded.
static func contains(model_path: String) -> bool:
	var model := model_path.get_file().get_basename().to_lower()
	for token in ["wall_tv", "wall_clock", "wall_mirror", "wall_urinal", "wall_hand_dryer", "fire_extinguisher", "painting", "aircondition", "white_board_big", "capboard_up_"]:
		if token in model:
			return true
	return false
