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
# 128 px keeps every cell at >= 1.4x the largest bake size at 80 px/m (1.5 m = 150 px, only 1.17x magnified)
# while the Lanczos pre-filter still removes the 313 px -> small aliasing; 128^2 RGBA8 = 64 KB per frame.
const SOURCE_SIZE := 128
const RELIEF_SIZE := 64
const RELIEF_CACHE_LIMIT := 64
# Slope-to-normal gain: edge bevels saturate, luminance detail inside a flake stays gentle.
const RELIEF_GAIN := 0.1
var sources: Dictionary = {}
var _relief_cache: Dictionary = {}


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
				source.resize(SOURCE_SIZE, SOURCE_SIZE, Image.INTERPOLATE_LANCZOS)
				source.clear_mipmaps()
				frames.append(source)
		sources[kind] = frames


## RGBA8 relief for one frame: R/G = tangent-space normal x/z (0.5 neutral, +x right, +z down in the image),
## A = height (0 where there is no debris). Built on the CPU from alpha softened by a box blur (rounded edges)
## and luminance (dark = crevice). Cached per frame and rotation; callers get a copy they may resize.
func relief(frame: Image, kind: String, index: int, turns: int) -> Image:
	var key := "%s:%d:%d" % [kind, index, posmod(turns, 4)]
	if not _relief_cache.has(key):
		if _relief_cache.size() >= RELIEF_CACHE_LIMIT:
			_relief_cache.clear()
		_relief_cache[key] = build_relief(frame, turns)
	return (_relief_cache[key] as Image).duplicate()


static func build_relief(frame: Image, turns: int = 0) -> Image:
	var small := frame.duplicate() as Image
	small.clear_mipmaps()
	for turn in posmod(turns, 4):
		small.rotate_90(CLOCKWISE)
	small.resize(RELIEF_SIZE, RELIEF_SIZE, Image.INTERPOLATE_LANCZOS)
	var n := RELIEF_SIZE
	var data := small.get_data()
	var alpha := PackedFloat32Array()
	var luma := PackedFloat32Array()
	alpha.resize(n * n)
	luma.resize(n * n)
	for i in n * n:
		alpha[i] = data[i * 4 + 3] / 255.0
		luma[i] = (data[i * 4] * 0.2126 + data[i * 4 + 1] * 0.7152 + data[i * 4 + 2] * 0.0722) / 255.0
	var soft := _box(_box(alpha, n), n)
	var height := PackedFloat32Array()
	height.resize(n * n)
	for i in n * n:
		height[i] = clampf(soft[i] * (0.5 + 0.5 * luma[i]), 0.0, 1.0)
	var out := PackedByteArray()
	out.resize(n * n * 4)
	for y in n:
		for x in n:
			var dx := height[y * n + mini(x + 1, n - 1)] - height[y * n + maxi(x - 1, 0)]
			var dz := height[mini(y + 1, n - 1) * n + x] - height[maxi(y - 1, 0) * n + x]
			var i := (y * n + x) * 4
			out[i] = roundi((clampf(-dx * 0.5 * n * RELIEF_GAIN, -1.0, 1.0) * 0.5 + 0.5) * 255.0)
			out[i + 1] = roundi((clampf(-dz * 0.5 * n * RELIEF_GAIN, -1.0, 1.0) * 0.5 + 0.5) * 255.0)
			out[i + 2] = 0
			out[i + 3] = roundi(height[y * n + x] * 255.0)
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, out)


static func _box(values: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var radius := 2
	var horizontal := PackedFloat32Array()
	horizontal.resize(n * n)
	var result := PackedFloat32Array()
	result.resize(n * n)
	for y in n:
		for x in n:
			var total := 0.0
			for k in range(-radius, radius + 1):
				total += values[y * n + clampi(x + k, 0, n - 1)]
			horizontal[y * n + x] = total / (radius * 2 + 1)
	for y in n:
		for x in n:
			var total := 0.0
			for k in range(-radius, radius + 1):
				total += horizontal[clampi(y + k, 0, n - 1) * n + x]
			result[y * n + x] = total / (radius * 2 + 1)
	return result


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
