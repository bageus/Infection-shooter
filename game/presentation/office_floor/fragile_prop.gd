extends RefCounted
## Glassware, fruit and paintings: any shot that does damage breaks them whole, leaving their material decals.

const GLASSWARE: Array[String] = ["09_glass.glb", "09_glass_2.glb"]
const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const BREAK_SOUND := preload("res://game/presentation/office_floor/prop_break_sound.gd")
const FLOOR_DEBRIS := preload("res://game/presentation/office_floor/prop_floor_debris.gd")
const PROP_DAMAGE := preload("res://game/features/combat/public/prop_damage_state.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")


static func applies(model_path: String) -> bool:
	var file := model_path.get_file()
	return is_glassware(model_path) or file.begins_with("09_fruit_") or file.begins_with("09_painting")


static func is_glassware(model_path: String) -> bool:
	var file := model_path.get_file()
	return file in GLASSWARE or file.begins_with("09_mug") or file.begins_with("09_fruit_plate")


## Every visible piece flies apart, the body stops blocking, and its material decals are scattered.
static func shatter(body: RigidBody3D, visual: Node3D, shapes: Array, damage: PROP_DAMAGE, floor_debris: FLOOR_DEBRIS, point: Vector3, direction: Vector3) -> void:
	if not damage.shatter():
		return
	var model_path: String = body.get("model_path")
	var effects: Node3D = body.get("effects_root")
	var glass := is_glassware(model_path)
	floor_debris.emit(body, model_path, "shatter", point, direction)
	var index := 0
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh != null and mesh.mesh != null and mesh.is_visible_in_tree():
			DAMAGE.spawn_piece(body, mesh, null, 0, index, direction, point, true, glass)
			index += 1
	if glass:
		SFX.play(effects if is_instance_valid(effects) else body.get_parent(), &"glass_break", point)
	else:
		BREAK_SOUND.play(body, effects, model_path, body.call("get_projectile_material"), point)
	visual.hide()
	for shape: CollisionShape3D in shapes:
		shape.set_deferred("disabled", true)
	body.collision_layer = 0
	body.freeze = true
