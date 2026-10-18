extends RefCounted
## Native-size source copy; original atlases remain immutable.
static func source(image: Image, opacity: float, turns: int = 0, scorch: bool = false) -> Image:
	var result := image.duplicate() as Image
	result.clear_mipmaps()
	if opacity < 1.0 or scorch:
		var bytes := result.get_data()
		for index in range(3, bytes.size(), 4):
			var soot := 1.0 - (bytes[index - 3] * 0.2126 + bytes[index - 2] * 0.7152 + bytes[index - 1] * 0.0722) / 255.0 if scorch else 1.0
			bytes[index] = roundi(bytes[index] * clampf(opacity, 0, 1) * soot)
			if scorch:
				bytes[index - 3] = 5
				bytes[index - 2] = 4
				bytes[index - 1] = 4
		result = Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes)
	for turn in posmod(turns, 4): result.rotate_90(CLOCKWISE)
	return result
