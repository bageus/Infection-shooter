extends RefCounted
## CPU blit of one blood mark texture into a floor tile image (RGBA8, TILE_PIXELS square).

const TILE_METERS := 4.0
const TILE_PIXELS := 128
const MAX_CELL_SPAN := 4
const MAX_CELL_INDEX := 100000.0
const PIXELS_PER_METER := TILE_PIXELS / TILE_METERS
const SOURCE_MAX_SIDE := 64
const SOURCE_CACHE_LIMIT := 32

var _sources: Dictionary = {}


## Returns a small RGBA8 copy of the texture, or null when it cannot be read.
func source_image(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var key := texture.get_instance_id()
	if _sources.has(key):
		return _sources[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var longest := maxi(image.get_width(), image.get_height())
	if longest > SOURCE_MAX_SIDE:
		var factor := float(SOURCE_MAX_SIDE) / longest
		image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_TRILINEAR)
	if _sources.size() >= SOURCE_CACHE_LIMIT:
		_sources.clear()
	_sources[key] = image
	return image


## Cells whose tiles a stain of this footprint touches.
static func cells_touched(position: Vector3, mark_basis: Basis, footprint: Vector2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not position.is_finite() or not footprint.is_finite() or not mark_basis.is_finite():
		return cells
	var half_x := (absf(mark_basis.x.x) * footprint.x + absf(mark_basis.z.x) * footprint.y) * 0.5
	var half_z := (absf(mark_basis.x.z) * footprint.x + absf(mark_basis.z.z) * footprint.y) * 0.5
	var low := Vector2i(_cell_index(position.x - half_x), _cell_index(position.z - half_z))
	var high := Vector2i(_cell_index(position.x + half_x), _cell_index(position.z + half_z))
	# A floor stain is at most a few metres across; anything wider is not a real mark.
	if high.x - low.x >= MAX_CELL_SPAN or high.y - low.y >= MAX_CELL_SPAN:
		return cells
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			cells.append(Vector2i(x, z))
	return cells


static func _cell_index(world_coordinate: float) -> int:
	return floori(clampf(world_coordinate / TILE_METERS, -MAX_CELL_INDEX, MAX_CELL_INDEX))


## Blends the stain into the tile at `cell`. u runs along world +x and v along +z,
## the same mapping a downward Decal uses for its albedo texture.
static func blit(tile: Image, cell: Vector2i, source: Image, position: Vector3, mark_basis: Basis, footprint: Vector2, tint: Color) -> void:
	var origin_x := cell.x * TILE_METERS
	var origin_z := cell.y * TILE_METERS
	var half_x := (absf(mark_basis.x.x) * footprint.x + absf(mark_basis.z.x) * footprint.y) * 0.5
	var half_z := (absf(mark_basis.x.z) * footprint.x + absf(mark_basis.z.z) * footprint.y) * 0.5
	var first_x := clampi(floori((position.x - half_x - origin_x) * PIXELS_PER_METER), 0, TILE_PIXELS - 1)
	var last_x := clampi(ceili((position.x + half_x - origin_x) * PIXELS_PER_METER), 0, TILE_PIXELS - 1)
	var first_z := clampi(floori((position.z - half_z - origin_z) * PIXELS_PER_METER), 0, TILE_PIXELS - 1)
	var last_z := clampi(ceili((position.z + half_z - origin_z) * PIXELS_PER_METER), 0, TILE_PIXELS - 1)
	var source_width := source.get_width()
	var source_height := source.get_height()
	for py in range(first_z, last_z + 1):
		var dz := origin_z + (py + 0.5) / PIXELS_PER_METER - position.z
		for px in range(first_x, last_x + 1):
			var dx := origin_x + (px + 0.5) / PIXELS_PER_METER - position.x
			var u := (dx * mark_basis.x.x + dz * mark_basis.x.z) / footprint.x + 0.5
			var v := (dx * mark_basis.z.x + dz * mark_basis.z.z) / footprint.y + 0.5
			if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
				continue
			var texel := source.get_pixel(int(u * source_width), int(v * source_height))
			var alpha := texel.a * tint.a
			if alpha < 0.01:
				continue
			var below := tile.get_pixel(px, py)
			var out_alpha := alpha + below.a * (1.0 - alpha)
			var rgb := (Vector3(texel.r * tint.r, texel.g * tint.g, texel.b * tint.b) * alpha + Vector3(below.r, below.g, below.b) * below.a * (1.0 - alpha)) / out_alpha
			tile.set_pixel(px, py, Color(rgb.x, rgb.y, rgb.z, out_alpha))
