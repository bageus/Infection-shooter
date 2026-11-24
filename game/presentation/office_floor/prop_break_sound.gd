extends RefCounted
## Select destruction timbre from the authored model, independently of durability.
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const IMPACT_MATERIAL := preload("res://game/presentation/office_floor/environment_impact_material.gd")


static func event_for(model_path: String, material: String) -> StringName:
	var model := model_path.get_file().to_lower()
	if "lamp" in model:
		return &"break_lamp"
	for appliance in ["microwave", "kettle", "kittle", "teapot", "coffee_machine", "coffee_vending", "water_cooler", "refrigerator"]:
		if appliance in model:
			return &"break_electronics"
	if material == "tech":
		return &"break_electronics"
	if "cardboard" in model or "archive_box" in model:
		return &"break_cardboard"
	if "crate" in model or "wood" in model or _wood_furniture(model):
		return &"break_wood"
	if material == "metal":
		return &"break_metal"
	return &"break_furniture"


# Shelves and cabinets are metal-costed but ring like wood, the same list the impact sound uses.
static func _wood_furniture(model: String) -> bool:
	for name in IMPACT_MATERIAL.WOOD_MODELS:
		if name in model:
			return true
	return false


static func play(host: Node3D, container: Node3D, model_path: String, material: String, point: Vector3) -> void:
	# The emitter may disappear on this frame; keep its voice with the effects.
	var parent: Node = container if is_instance_valid(container) else host.get_parent()
	SFX.play(parent, event_for(model_path, material), point)
