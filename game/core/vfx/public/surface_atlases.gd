extends RefCounted
## Immutable authored surface atlases. Cells run left-to-right, top-to-bottom.
const BULLET := preload("res://models/objects/textures/bullet_decals/Eight-panel bullet and scorch decal atlas.png")
const GLASS := preload("res://models/objects/textures/glass_decals/Glass_Cracks_Atlas_4x2.png")
const SHADER := preload("res://game/core/vfx/surface_atlas.gdshader")
const GLASS_CENTERS: Array[Vector2] = [Vector2(.23, .55), Vector2(.54, .54), Vector2(.535, .515),
	Vector2(.515, .525), Vector2(.52, .5), Vector2(.505, .49), Vector2(.52, .535), Vector2(.46, .46)]


static func material(texture: Texture2D, cell: int) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter("atlas", texture)
	result.set_shader_parameter("scorch", texture == BULLET and cell >= 5)
	var guard := Vector2(.5 / texture.get_width(), .5 / texture.get_height())
	result.set_shader_parameter("region", Vector4((cell % 4) * .25 + guard.x,
		floori(float(cell) / 4.0) * .5 + guard.y, .25 - guard.x * 2, .5 - guard.y * 2))
	result.render_priority = 1
	return result
