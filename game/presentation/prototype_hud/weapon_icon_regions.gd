extends RefCounted

# Extract connected visible artwork once; atlas whitespace is not HUD artwork.
static func extract(source: Texture2D) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var image := source.get_image()
	if image == null:
		return result
	if image.is_compressed() and image.decompress() != OK:
		return result
	image.convert(Image.FORMAT_RGBA8)
	_remove_plain_background(image)
	var sample := image.duplicate() as Image
	var factor := minf(1.0, 512.0 / maxi(image.get_width(), image.get_height()))
	sample.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)))
	var regions := _components(sample)
	regions = _reading_order(regions)
	for bounds in regions:
		var start := Vector2i(Vector2(bounds.position) / factor)
		var end := Vector2i((Vector2(bounds.end) + Vector2.ONE) / factor)
		var area := Rect2i(start, end - start).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var icon := image.get_region(area)
		var used := icon.get_used_rect()
		if not used.has_area():
			continue
		icon = icon.get_region(used)
		icon.generate_mipmaps()
		result.append(ImageTexture.create_from_image(icon))
	return result


static func _remove_plain_background(image: Image) -> void:
	if image.detect_alpha() != Image.ALPHA_NONE:
		return
	var background := image.get_pixel(0, 0)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			var difference := Vector3(pixel.r - background.r, pixel.g - background.g, pixel.b - background.b).length()
			if difference < 0.12:
				pixel.a = 0.0
				image.set_pixel(x, y, pixel)


static func _components(image: Image) -> Array[Rect2i]:
	var width := image.get_width()
	var height := image.get_height()
	var mask := PackedByteArray()
	mask.resize(width * height)
	for y in height:
		for x in width:
			mask[y * width + x] = 1 if image.get_pixel(x, y).a > 0.12 else 0
	var regions: Array[Rect2i] = []
	for start in mask.size():
		if mask[start] == 0:
			continue
		var queue := PackedInt32Array([start])
		mask[start] = 0
		var cursor := 0
		var minimum := Vector2i(start % width, floori(float(start) / width))
		var maximum := minimum
		while cursor < queue.size():
			var index := queue[cursor]
			cursor += 1
			var point := Vector2i(index % width, floori(float(index) / width))
			minimum = minimum.min(point)
			maximum = maximum.max(point)
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = point + step
				if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
					continue
				var neighbour := next.y * width + next.x
				if mask[neighbour] == 1:
					mask[neighbour] = 0
					queue.append(neighbour)
		if queue.size() >= maxi(32, roundi(width * height * 0.001)):
			regions.append(Rect2i(minimum, maximum - minimum + Vector2i.ONE))
	return regions


static func _reading_order(regions: Array[Rect2i]) -> Array[Rect2i]:
	regions.sort_custom(_top_first)
	var rows: Array[Array] = []
	for region in regions:
		var matched := false
		for row in rows:
			var reference: Rect2i = row[0]
			if absf(region.get_center().y - reference.get_center().y) < maxf(region.size.y, reference.size.y) * 0.6:
				row.append(region)
				matched = true
				break
		if not matched:
			rows.append([region])
	var result: Array[Rect2i] = []
	for row in rows:
		row.sort_custom(_left_first)
		for region in row:
			result.append(region)
	return result


static func _top_first(a: Rect2i, b: Rect2i) -> bool:
	return a.get_center().y < b.get_center().y


static func _left_first(a: Rect2i, b: Rect2i) -> bool:
	return a.position.x < b.position.x
