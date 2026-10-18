extends RefCounted
## Small CPU source cache owned by the floor; original imported textures stay immutable.
const ROOT := "res://models/objects/textures/"
const DEFINITIONS := {
	"glass": [[ROOT + "glass_decals/4x4 glass debris texture atlas.png", 4, 4]],
	"paper": [[ROOT + "paper/Crumpled and charred office paper atlas.png", 4, 4],
		[ROOT + "paper/Ten torn paper debris sprites.png", 5, 2]],
	"wood": [[ROOT + "wood_decals/Office wood debris texture atlas-1.png", 4, 4],
		[ROOT + "wood_decals/Transparent 4×4 Wood Debris Sprite Atlas-2.png", 4, 4]],
	"cardboard": [[ROOT + "paper/Cardboard Debris Sprite Atlas.png", 4, 4]],
	"plastic": [[ROOT + "plastic/Office electronics plastic debris atlas.png", 4, 4]],
	"fabric": [[ROOT + "upholstery/Torn upholstery debris sprite atlas.png", 4, 4]],
	"extinguisher": [[ROOT + "fire_extinguisher_layers/Red extinguisher debris texture atlas.png", 4, 4]],
}
const SURFACE_DEFINITIONS := {
	"glass_fracture": [[ROOT + "glass_decals/Transparent glass fracture decal atlas.png", 4, 4]],
	"glass_impact": [[ROOT + "glass_decals/Glass_Cracks_Atlas_4x2.png", 4, 2]],
	"bullet": [[ROOT + "bullet_decals/Eight-panel bullet and scorch decal atlas.png", 4, 2]],
	"wall_damage": [[ROOT + "wall/Office wall damage decal atlas.png", 4, 4]],
	"wall_scuff": [[ROOT + "wall/Soft wall and column scuff atlas.png", 4, 4]],
	"floor_damage": [[ROOT + "floor/Office Tile Damage Decal Atlas.png", 4, 4]],
	"floor_scuff": [[ROOT + "floor/Subtle sixteen-cell floor scuff atlas.png", 4, 4]],
}
const ROUGHNESS := {"glass": 0.15, "paper": 0.96, "wood": 0.86,
	"cardboard": 0.94, "plastic": 0.57, "fabric": 0.99, "extinguisher": 0.5}
var sources: Dictionary = {}


func prepare() -> void:
	var definitions := DEFINITIONS.merged(SURFACE_DEFINITIONS)
	for kind: String in definitions:
		if sources.has(kind):
			continue
		var frames: Array[Image] = []
		for definition: Array in definitions[kind]:
			var texture := load(str(definition[0])) as Texture2D
			if texture == null:
				continue
			var image := texture.get_image()
			if image == null or image.is_empty():
				continue
			if image.is_compressed() and image.decompress() != OK:
				continue
			image.convert(Image.FORMAT_RGBA8)
			var columns: int = definition[1]
			var rows: int = definition[2]
			for index in columns * rows:
				var row := floori(float(index) / columns)
				var low := Vector2i(floori((index % columns) * image.get_width() / float(columns)), floori(row * image.get_height() / float(rows)))
				var high := Vector2i(floori((index % columns + 1) * image.get_width() / float(columns)), floori((row + 1) * image.get_height() / float(rows)))
				var source := image.get_region(Rect2i(low, high - low))
				source.resize(96, 96, Image.INTERPOLATE_LANCZOS)
				source.clear_mipmaps()
				frames.append(source)
		sources[kind] = frames


static func frame_count(kind: String) -> int:
	var count := 0
	for definition: Array in DEFINITIONS.get(kind, SURFACE_DEFINITIONS.get(kind, [])):
		count += int(definition[1]) * int(definition[2])
	return count


static func choose_frame(kind: String, distant: bool, rng: RandomNumberGenerator) -> int:
	if kind == "paper" and distant:
		return rng.randi_range(16, 25) # Single torn scraps, not distant whole wads.
	if distant:
		return rng.randi_range(0, 3) + (16 * rng.randi_range(0, 1) if kind == "wood" else 0)
	return rng.randi_range(0, frame_count(kind) - 1)
