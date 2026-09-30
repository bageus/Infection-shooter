extends RefCounted

# Semantic order is stable even though the launcher occupies the top row.
# Bounds follow the artwork, excluding the atlas's connected pale halos.
const REFERENCE_SIZE := Vector2(1774, 887)
const ARTWORK_BOUNDS := [
	Rect2(24, 522, 432, 256), # Rifle
	Rect2(478, 540, 245, 238), # Pistol
	Rect2(760, 531, 320, 250), # Uzi
	Rect2(1070, 538, 445, 230), # Shotgun
	Rect2(1513, 531, 228, 240), # Antidote
	Rect2(650, 99, 476, 266), # Grenade launcher
]


static func extract(source: Texture2D) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var image := source.get_image()
	if image == null:
		return result
	if image.is_compressed() and image.decompress() != OK:
		return result
	var ratio := Vector2(image.get_size()) / REFERENCE_SIZE
	for bounds in ARTWORK_BOUNDS:
		var start := Vector2i((bounds.position * ratio).floor())
		var finish := Vector2i((bounds.end * ratio).ceil())
		var area := Rect2i(start, finish - start).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var icon := image.get_region(area)
		icon.generate_mipmaps()
		result.append(ImageTexture.create_from_image(icon))
	return result
