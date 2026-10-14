extends RefCounted
## Select destruction timbre from the authored model, independently of durability.
const SFX := preload("res://game/core/audio/public/sound_events.gd")


static func event_for(model_path: String, material: String) -> StringName:
	var model := model_path.get_file().to_lower()
	if "lamp" in model:
		return &"break_lamp"
	for appliance in ["microwave", "kettle", "teapot", "coffee_machine", "coffee_vending", "water_cooler", "refrigerator"]:
		if appliance in model:
			return &"break_electronics"
	if material == "tech":
		return &"break_electronics"
	if "cardboard" in model or "archive_box" in model:
		return &"break_cardboard"
	if "crate" in model or "wood" in model:
		return &"break_wood"
	if material == "metal":
		return &"break_metal"
	return &"break_furniture"


static func play(host: Node3D, container: Node3D, model_path: String, material: String, point: Vector3) -> void:
	# The emitter may disappear on this frame; keep its voice with the effects.
	var parent: Node = container if is_instance_valid(container) else host.get_parent()
	SFX.play(parent, event_for(model_path, material), point)
