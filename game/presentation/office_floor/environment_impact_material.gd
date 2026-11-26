extends RefCounted
## Impact sound material for environment props, chosen by model file name.

const WOOD_MODELS := ["01_wood_slat_partition", "03_book_case", "03_bookshelf", "03_file_cabinet", "03_drawer_cabinet"]
# Ducts, pipes and barrels ring like pipes; metal doors and elevator cabins like doors.
const PIPE_MODELS := ["_duct_", "_pipe_", "_barrel_"]
# Bullet-resistant tank glass: shots ring like armor.
const ARMORED_GLASS_MODELS := ["Containment_Tank_"]
const DOOR_MODELS := ["metal_door", "elevator"]
# Barrels are steel drums: shots ring like pipes, but a barrel that lands or bumps rings like metal.
const STEEL_KNOCK_MODELS := ["_barrel_"]


static func resolve(model_path: String, projectile_material: String) -> String:
	for model in WOOD_MODELS:
		if model in model_path: return "wood"
	for model in PIPE_MODELS:
		if model in model_path: return "pipe"
	for model in ARMORED_GLASS_MODELS:
		if model in model_path: return "metal"
	for model in DOOR_MODELS:
		if model in model_path: return "door"
	return projectile_material


## Material of a knock or landing (fall sound), which can differ from the impact sound of a shot.
static func knock(model_path: String, projectile_material: String) -> String:
	for model in STEEL_KNOCK_MODELS:
		if model in model_path: return "metal"
	return projectile_material
