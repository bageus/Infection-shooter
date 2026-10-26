extends RefCounted

# Wall-mounted environment GLBs; structural walls and freestanding boards are excluded.
static func contains(model_path: String) -> bool:
	if "/enviroments/13/" in model_path:
		return true
	# Pipes and ducts start as their name says: wall pieces hug a wall, floor pieces stand apart.
	if is_adjustable(model_path):
		return not ("_floor_" in model_path.get_file())
	var model := model_path.get_file().get_basename().to_lower()
	for token in ["01_vectrion_destructible", "wall_tv", "wall_clock", "wall_mirror", "wall_urinal", "wall_hand_dryer", "fire_extinguisher", "painting", "aircondition", "white_board_big", "white_board_stand", "capboard_up_"]:
		if token in model:
			return true
	return false


# Pipes and ducts can hug a wall or stand apart from it; the planner lets the player choose.
static func is_adjustable(model_path: String) -> bool:
	var model := model_path.get_file().get_basename().to_lower()
	return model.begins_with("01_pipe_") or model.begins_with("01_duct_rect")
