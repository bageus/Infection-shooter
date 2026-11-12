extends SceneTree
## Enemy glow: the skin shader carries each enemy's emission mask (eyes, blisters).

const SKIN := preload("res://game/features/infected/body_skin_materials.gd")
const ENEMIES := ["Hunger", "Brute", "Revenant", "Colossus", "Titan", "Horde"]
var failures := 0


func _init() -> void:
	for enemy: String in ENEMIES:
		var original := load("res://models/objects/characters/enemy/game/%s_game.tres" % enemy) as BaseMaterial3D
		var skin := SKIN.create_material(original)
		if original.emission_texture == null or skin.get_shader_parameter("emission_texture") != original.emission_texture or not skin.get_shader_parameter("use_glow"):
			failures += 1
			push_error("FAIL: %s skin lost its glow mask" % enemy)
		var plain := SKIN.create_material(StandardMaterial3D.new())
		if plain.get_shader_parameter("use_glow"):
			failures += 1
			push_error("FAIL: material without emission glows")
	print("Enemy glow tests: %d failures" % failures)
	quit(failures)
