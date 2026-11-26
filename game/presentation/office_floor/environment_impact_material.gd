extends RefCounted
## Impact sound material for environment props, chosen by model file name.

const WOOD_MODELS := ["01_wood_slat_partition", "03_book_case", "03_bookshelf", "03_file_cabinet", "03_drawer_cabinet"]
# Metal doors and elevator cabins ring like doors.
# Bullet-resistant tank glass: shots ring like armor.
const ARMORED_GLASS_MODELS := ["Containment_Tank_"]
const DOOR_MODELS := ["metal_door", "elevator"]


static func resolve(model_path: String, projectile_material: String) -> String:
	for model in WOOD_MODELS:
		if model in model_path: return "wood"
	for model in ARMORED_GLASS_MODELS:
		if model in model_path: return "metal"
	for model in DOOR_MODELS:
		if model in model_path: return "door"
	return projectile_material

