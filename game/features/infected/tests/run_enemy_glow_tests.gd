extends SceneTree
## Enemy glow: only the Colossus glows, and the skin shader carries its blister mask.

const SKIN := preload("res://game/features/infected/body_skin_materials.gd")
const OTHERS := ["Hunger", "Brute", "Revenant", "Titan", "Horde"]
var failures := 0


func _init() -> void:
	var colossus := load("res://models/objects/characters/enemy/game/Colossus_game.tres") as BaseMaterial3D
	var skin := SKIN.create_material(colossus)
	if colossus.emission_texture == null or skin.get_shader_parameter("emission_texture") != colossus.emission_texture or not skin.get_shader_parameter("use_glow"):
		failures += 1
		push_error("FAIL: Colossus skin lost its glow mask")
	for enemy: String in OTHERS:
		var original := load("res://models/objects/characters/enemy/game/%s_game.tres" % enemy) as BaseMaterial3D
		if original.emission_enabled or SKIN.create_material(original).get_shader_parameter("use_glow"):
			failures += 1
			push_error("FAIL: %s must not glow" % enemy)
	print("Enemy glow tests: %d failures" % failures)
	quit(failures)
