extends RefCounted
## Mission-local glass pixels. Native image blits, no per-shard nodes or callbacks.
const ATLAS := preload("res://models/objects/textures/glass_decals/4x4 glass debris texture atlas.png")
const METERS := 8.0
const PIXELS := 512
const MAX_TILES := 16
const MAX_QUEUE := 64
const MAX_DENSITY := 4
const STAMPS_PER_STEP := 2
var origin := Vector2.ZERO
var valid_cells: Dictionary = {}
var tiles: Dictionary = {}
var queue: Array[Dictionary] = []
var _sources: Array[Image] = []
var _changed: Callable
var uploads := 0


func _init(changed: Callable) -> void:
	_changed = changed


func prepare() -> void:
	if not _sources.is_empty():
		return
	var image := ATLAS.get_image()
	if image == null or image.is_empty():
		return
	if image.is_compressed() and image.decompress() != OK:
		return
	image.convert(Image.FORMAT_RGBA8)
	# Fractional boundaries are intentional: the authored atlas is 1254 square.
	for index in 16:
		var row := floori(float(index) / 4.0)
		var low := Vector2i(floori((index % 4) * image.get_width() / 4.0), floori(row * image.get_height() / 4.0))
		var high := Vector2i(floori((index % 4 + 1) * image.get_width() / 4.0), floori((row + 1) * image.get_height() / 4.0))
		var source := image.get_region(Rect2i(low, high - low))
		source.resize(96, 96, Image.INTERPOLATE_LANCZOS)
		_sources.append(source)


func stamp(at: Vector2, frame: int, size: float, turns: int = 0) -> bool:
	if not at.is_finite() or not is_finite(size) or size < 0.25 or size > 1.5 or frame < 0 or frame >= 16:
		return false
	if queue.size() >= MAX_QUEUE:
		return false
	queue.append({"at": at, "frame": frame, "size": size, "turns": posmod(turns, 4)})
	return true


func cell_at(at: Vector2) -> Vector2i:
	return Vector2i(floori((at.x - origin.x) / METERS), floori((at.y - origin.y) / METERS))


func step() -> bool:
	prepare()
	for index in STAMPS_PER_STEP:
		if queue.is_empty():
			break
		_apply(queue.pop_front())
	# Coalesce all writes; upload at most one 1 MiB section per frame.
	for cell: Vector2i in tiles:
		var tile: Dictionary = tiles[cell]
		if not tile.dirty:
			continue
		if tile.texture == null:
			tile.texture = ImageTexture.create_from_image(tile.image)
			_changed.call(cell, tile.texture)
		else:
			(tile.texture as ImageTexture).update(tile.image)
		tile.dirty = false
		uploads += 1
		break
	return not queue.is_empty() or _has_dirty()


func _apply(request: Dictionary) -> void:
	if _sources.size() != 16:
		return
	var at: Vector2 = request.at
	var center := cell_at(at)
	var density_cell := Vector2i(floori(at.x), floori(at.y))
	if tiles.has(center) and int(tiles[center].density.get(density_cell, 0)) >= MAX_DENSITY:
		return
	var source := _sources[request.frame].duplicate() as Image
	for turn in int(request.turns):
		source.rotate_90(CLOCKWISE)
	var side := roundi(float(request.size) * PIXELS / METERS)
	source.resize(side, side, Image.INTERPOLATE_BILINEAR)
	var low := at - Vector2.ONE * float(request.size) * 0.5
	var first := cell_at(low)
	var last := cell_at(low + Vector2.ONE * float(request.size))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if not valid_cells.is_empty() and not valid_cells.has(cell):
				continue
			var tile := _tile(cell)
			var offset := Vector2i((((low - origin) / METERS - Vector2(cell)) * PIXELS).floor())
			# Native clipping also handles marks crossing a section boundary.
			(tile.image as Image).blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), offset)
			tile.dirty = true
	if tiles.has(center):
		var density: Dictionary = tiles[center].density
		density[density_cell] = int(density.get(density_cell, 0)) + 1


func _tile(cell: Vector2i) -> Dictionary:
	if tiles.has(cell):
		# Insertion order is the bounded least-recently-written eviction queue.
		var retained: Dictionary = tiles[cell]
		tiles.erase(cell)
		tiles[cell] = retained
		return retained
	if tiles.size() >= MAX_TILES:
		var oldest: Vector2i = tiles.keys()[0]
		_changed.call(oldest, null)
		tiles.erase(oldest)
	var image := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var tile := {"image": image, "texture": null, "dirty": false, "density": {}}
	tiles[cell] = tile
	return tile


func _has_dirty() -> bool:
	for tile: Dictionary in tiles.values():
		if tile.dirty:
			return true
	return false


func clear() -> void:
	for cell: Vector2i in tiles:
		_changed.call(cell, null)
	tiles.clear()
	queue.clear()
