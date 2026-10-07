extends RefCounted

# Measured against the owner's transparent atlas on 2026-10-07 (alpha > 0.12
# component bounds, padded 4 px for the antialiased halo).
# Stable semantic order: rifle, pistol, uzi, shotgun, antidote, launcher, key.
const REFERENCE_SIZE := Vector2(1774, 887)
const ARTWORK_BOUNDS := [
	Rect2(310, 617, 481, 233), # Rifle (M4)
	Rect2(494, 356, 250, 220), # Pistol
	Rect2(767, 350, 315, 251), # Uzi
	Rect2(1084, 357, 439, 237), # Shotgun
	Rect2(1534, 351, 211, 233), # Antidote
	Rect2(642, 30, 495, 256), # Grenade launcher
	Rect2(40, 634, 222, 211), # Emergency key
]


static func extract(source: Texture2D) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var image := source.get_image()
	if image == null:
		return result
	if image.is_compressed() and image.decompress() != OK:
		return result
	image.convert(Image.FORMAT_RGBA8)
	var ratio := Vector2(image.get_size()) / REFERENCE_SIZE
	for bounds in ARTWORK_BOUNDS:
		var start := Vector2i((bounds.position * ratio).floor())
		var finish := Vector2i((bounds.end * ratio).ceil())
		var area := Rect2i(start, finish - start).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var icon := image.get_region(area)
		_keep_largest_component(icon)
		icon.generate_mipmaps()
		result.append(ImageTexture.create_from_image(icon))
	return result


# Neighboring weapon AABBs overlap slightly; discard only foreign components.
static func _keep_largest_component(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var labels := PackedInt32Array()
	labels.resize(width * height)
	var largest := 0
	var largest_size := 0
	var component := 0
	for start in labels.size():
		if labels[start] != 0 or image.get_pixel(start % width, floori(float(start) / width)).a <= 0.12:
			continue
		component += 1
		var queue := PackedInt32Array([start])
		labels[start] = component
		var cursor := 0
		while cursor < queue.size():
			var index := queue[cursor]
			cursor += 1
			var point := Vector2i(index % width, floori(float(index) / width))
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = point + step
				if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
					continue
				var neighbour := next.y * width + next.x
				if labels[neighbour] == 0 and image.get_pixelv(next).a > 0.12:
					labels[neighbour] = component
					queue.append(neighbour)
		if queue.size() > largest_size:
			largest = component
			largest_size = queue.size()
	if largest == 0:
		return
	for y in height:
		for x in width:
			var index := y * width + x
			if labels[index] == largest:
				continue
			# Retain the original faint antialiasing immediately along this edge.
			var edge := labels[index] == 0 and ((x > 0 and labels[index - 1] == largest) or (x + 1 < width and labels[index + 1] == largest) or (y > 0 and labels[index - width] == largest) or (y + 1 < height and labels[index + width] == largest))
			if not edge:
				var pixel := image.get_pixel(x, y)
				pixel.a = 0.0
				image.set_pixel(x, y, pixel)
