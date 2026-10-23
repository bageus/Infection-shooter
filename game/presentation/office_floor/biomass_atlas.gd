extends RefCounted
## Volumetric blood biomass (ADR-0061): six hand-painted relief cells packed in
## one padded atlas. The albedo atlas carries the silhouette in its alpha; the
## relief atlas stores the tangent normal in R and G and the height in B.

const ALBEDO_PATH := "res://assets/biomass/biomass_albedo.png"
const RELIEF_PATH := "res://assets/biomass/biomass_relief.png"
const COLUMNS := 3
const ROWS := 2
const CELL := Vector2i(418, 627)
## Transparent gutter around each cell so mip levels never bleed between cells.
const PAD := 16
const TILE := Vector2i(450, 659)
const ATLAS := Vector2i(1350, 1318)
const COUNT := 6
## Long side of one cell is one metre at scale 1, like every other blood decal.
const FOOTPRINT := Vector2(418.0 / 627.0, 1.0)

static var _albedo_image: Image
static var _relief_image: Image


static func is_biomass_id(texture_id: String) -> bool:
	return texture_id.begins_with("biomass_")


static func ids() -> PackedStringArray:
	var result := PackedStringArray()
	for index in COUNT:
		result.append("biomass_%02d" % (index + 1))
	return result


static func cell_of(texture_id: String) -> int:
	return clampi(int(texture_id.get_slice("_", 1)) - 1, 0, COUNT - 1)


## Pixel of the cell's top-left corner inside the atlas.
static func cell_origin(cell: int) -> Vector2i:
	@warning_ignore("integer_division")
	var row := cell / COLUMNS
	return Vector2i((cell % COLUMNS) * TILE.x + PAD, row * TILE.y + PAD)


## Cell interior as a rectangle in 0..1 atlas UV space.
static func uv_rect(cell: int) -> Rect2:
	var origin := Vector2(cell_origin(cell))
	return Rect2(origin / Vector2(ATLAS), Vector2(CELL) / Vector2(ATLAS))


static func albedo_texture() -> Texture2D:
	return load(ALBEDO_PATH) as Texture2D


static func relief_texture() -> Texture2D:
	return load(RELIEF_PATH) as Texture2D


## Uncompressed copies for CPU fusion. Call on the main thread; the returned
## bytes are read-only and safe to hand to a worker.
static func albedo_bytes() -> PackedByteArray:
	if _albedo_image == null:
		_albedo_image = _readable(albedo_texture(), Image.FORMAT_RGBA8)
	return _albedo_image.get_data()


static func relief_bytes() -> PackedByteArray:
	if _relief_image == null:
		_relief_image = _readable(relief_texture(), Image.FORMAT_RGB8)
	return _relief_image.get_data()


static func _readable(texture: Texture2D, format: Image.Format) -> Image:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	if image.get_format() != format:
		image.convert(format)
	return image
