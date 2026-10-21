extends RefCounted
## Shared mission-local debris pixels; the original glass entry point stays compatible.
const ATLASES := preload("res://game/presentation/office_floor/debris_atlases.gd")
const PIXEL_OPS := preload("res://game/presentation/office_floor/decal_pixels.gd")
const ATLAS := preload("res://models/objects/textures/glass_decals/4x4 glass debris texture atlas.png")
const METERS := 8.0
# 80 px/m (was 64): a 0.25 m flake is 20 px wide instead of 16 before it is magnified on screen.
const PIXELS := 640
# Relief (normal xy + height) is smooth, so 32 px/m is enough; floor damage/scuff layers stay 32 px/m.
const RELIEF_PIXELS := 256
const LAYER_PIXELS := 256
# Evicted tiles are kept as lossless PNG (sparse decals shrink to a few KB); only an image whose PNG
# exceeds ARCHIVE_PNG_LIMIT falls back to a Lanczos-shrunk copy of ARCHIVE_FALLBACK px.
const ARCHIVE_PNG_LIMIT := 98304
const ARCHIVE_FALLBACK := 192
const MAX_TILES := 16
const MIN_SIZE := 0.08 # Real flakes are small; 0.08 m is 6 px at 80 px/m.
const MAX_QUEUE := 64
const MAX_DENSITY := 4
const STAMPS_PER_STEP := 2
var origin := Vector2.ZERO
var valid_cells: Dictionary = {}
var tiles: Dictionary = {}
# Evicted tiles keep their CPU pixels so decals survive the GPU cap. Bound: one entry per cell ever
# decalled (<= ~80 cells on the 80x60 m floor). Each image is stored lossless as PNG when it is <= 96 KB
# (typical: a few KB to tens of KB), otherwise as a shrunk copy (<= 192^2 RGBA8 = 147 KB), so restoring
# does not stack bilinear blur on every evict/restore round trip.
var _archive: Dictionary = {}
var queue: Array[Dictionary] = []
var _sources: Array[Image] = []
var _changed: Callable
var uploads := 0
var _atlases := ATLASES.new()


func _init(changed: Callable) -> void:
	_changed = changed


func prepare() -> void:
	if not _sources.is_empty():
		return
	_atlases.prepare()
	_sources = _atlases.sources.get("glass", [] as Array[Image])


func stamp(at: Vector2, frame: int, size: float, turns: int = 0, kind: String = "glass", opacity: float = 1.0) -> bool:
	if not is_finite(opacity) or opacity <= 0.0 or not at.is_finite() or not is_finite(size) or size < MIN_SIZE or size > 1.5 or frame < 0 or frame >= ATLASES.frame_count(kind):
		return false
	if queue.size() >= MAX_QUEUE:
		return false
	queue.append({"at": at, "frame": frame, "size": size, "turns": posmod(turns, 4), "kind": kind, "opacity": clampf(opacity, 0, 1)})
	return true


func cell_at(at: Vector2) -> Vector2i:
	return Vector2i(floori((at.x - origin.x) / METERS), floori((at.y - origin.y) / METERS))


func step() -> bool:
	prepare()
	for index in STAMPS_PER_STEP:
		if queue.is_empty():
			break
		_apply(queue.pop_front())
	# Coalesce all writes; upload one section (RGBA8 color + compact R8 surface).
	for cell: Vector2i in tiles:
		var tile: Dictionary = tiles[cell]
		if not tile.dirty:
			continue
		var rebound: bool = tile.texture == null
		if tile.texture == null:
			tile.texture = ImageTexture.create_from_image(tile.image)
			tile.surface_texture = ImageTexture.create_from_image(tile.surface_image)
			tile.relief_texture = ImageTexture.create_from_image(tile.relief_image)
		else:
			(tile.texture as ImageTexture).update(tile.image)
			(tile.surface_texture as ImageTexture).update(tile.surface_image)
			(tile.relief_texture as ImageTexture).update(tile.relief_image)
		for layer: Dictionary in tile.layers.values():
			if layer.texture == null:
				layer.texture = ImageTexture.create_from_image(layer.image)
				rebound = true
			else: (layer.texture as ImageTexture).update(layer.image)
		if rebound: _changed.call(cell, tile.texture)
		tile.dirty = false
		uploads += 1
		break
	return not queue.is_empty() or _has_dirty()


func _apply(request: Dictionary) -> void:
	var frames: Array = _atlases.sources.get(request.kind, [])
	if int(request.frame) >= frames.size():
		return
	var at: Vector2 = request.at
	var center := cell_at(at)
	var layer_id := 0 if request.kind in ["floor_damage", "bullet"] else (1 if request.kind == "floor_scuff" else 2)
	var density_cell: Variant = Vector2i(floori(at.x), floori(at.y))
	if layer_id != 2: density_cell = Vector3i(floori(at.x), floori(at.y), layer_id)
	if tiles.has(center) and int(tiles[center].density.get(density_cell, 0)) >= MAX_DENSITY:
		return
	var source := PIXEL_OPS.source(frames[request.frame], request.opacity, request.turns, request.kind == "bullet" and request.frame >= 5)
	var resolution := PIXELS if layer_id == 2 else LAYER_PIXELS
	var side := roundi(float(request.size) * resolution / METERS)
	# Lanczos is scale-aware; Godot's bilinear only reads 2x2 texels and aliases when shrinking.
	source.resize(side, side, Image.INTERPOLATE_LANCZOS)
	var surface: Image
	var relief: Image
	var relief_side := 0
	if layer_id == 2:
		surface = Image.create(side, side, false, Image.FORMAT_R8)
		surface.fill(Color(float(ATLASES.ROUGHNESS.get(request.kind, 0.9)), 0, 0))
		relief_side = maxi(roundi(float(request.size) * RELIEF_PIXELS / METERS), 2)
		relief = _atlases.relief(frames[request.frame], request.kind, int(request.frame), int(request.turns))
		relief.resize(relief_side, relief_side, Image.INTERPOLATE_LANCZOS)
	var low := at - Vector2.ONE * float(request.size) * 0.5
	var first := cell_at(low)
	var last := cell_at(low + Vector2.ONE * float(request.size))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if not valid_cells.is_empty() and not valid_cells.has(cell):
				continue
			var tile := _tile(cell)
			var offset := Vector2i((((low - origin) / METERS - Vector2(cell)) * resolution).floor())
			# Native clipping also handles marks crossing a section boundary.
			var target: Image = tile.image
			if layer_id < 2:
				if not tile.layers.has(layer_id):
					var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
					image.fill(Color.TRANSPARENT)
					tile.layers[layer_id] = {"image": image, "texture": null}
				target = tile.layers[layer_id].image
			target.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), offset)
			if layer_id == 2:
				(tile.surface_image as Image).blit_rect_mask(surface, source, Rect2i(Vector2i.ZERO, source.get_size()), offset)
				var relief_offset := Vector2i((((low - origin) / METERS - Vector2(cell)) * RELIEF_PIXELS).floor())
				(tile.relief_image as Image).blend_rect(relief, Rect2i(Vector2i.ZERO, relief.get_size()), relief_offset)
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
		var evicted: Dictionary = tiles[oldest]
		evicted.texture = null
		evicted.surface_texture = null
		evicted.relief_texture = null
		evicted.dirty = true
		for layer: Dictionary in evicted.layers.values():
			layer.texture = null
			layer.image = _pack(layer.image, LAYER_PIXELS / 2)
		evicted.image = _pack(evicted.image, ARCHIVE_FALLBACK)
		evicted.surface_image = _pack(evicted.surface_image, ARCHIVE_FALLBACK)
		evicted.relief_image = _pack(evicted.relief_image, RELIEF_PIXELS / 2)
		_archive[oldest] = evicted
		tiles.erase(oldest)
	if _archive.has(cell):
		var restored: Dictionary = _archive[cell]
		restored.image = _unpack(restored.image, Image.FORMAT_RGBA8, PIXELS)
		restored.surface_image = _unpack(restored.surface_image, Image.FORMAT_R8, PIXELS)
		restored.relief_image = _unpack(restored.relief_image, Image.FORMAT_RGBA8, RELIEF_PIXELS)
		for layer: Dictionary in restored.layers.values():
			layer.image = _unpack(layer.image, Image.FORMAT_RGBA8, LAYER_PIXELS)
		tiles[cell] = restored
		_archive.erase(cell)
		return restored
	var image := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var surface := Image.create(PIXELS, PIXELS, false, Image.FORMAT_R8)
	surface.fill(Color(0.6, 0, 0))
	var relief := Image.create(RELIEF_PIXELS, RELIEF_PIXELS, false, Image.FORMAT_RGBA8)
	relief.fill(Color(0.5, 0.5, 0.0, 0.0)) # Flat normal, zero height.
	var tile := {"image": image, "texture": null, "surface_image": surface,
		"surface_texture": null, "relief_image": relief, "relief_texture": null,
		"layers": {}, "dirty": false, "density": {}}
	tiles[cell] = tile
	return tile


func _pack(source: Image, fallback: int) -> Variant:
	var bytes := source.save_png_to_buffer()
	if bytes.size() <= ARCHIVE_PNG_LIMIT:
		return bytes
	var copy := source.duplicate() as Image
	copy.resize(fallback, fallback, Image.INTERPOLATE_LANCZOS)
	return copy


func _unpack(stored: Variant, format: Image.Format, side: int) -> Image:
	var image := Image.new()
	if stored is PackedByteArray:
		image.load_png_from_buffer(stored)
	else:
		image = stored as Image
		if image.get_width() != side:
			image.resize(side, side, Image.INTERPOLATE_BILINEAR)
	if image.get_format() != format:
		image.convert(format)
	return image


func _has_dirty() -> bool:
	for tile: Dictionary in tiles.values():
		if tile.dirty:
			return true
	return false


func clear() -> void:
	for cell: Vector2i in tiles:
		_changed.call(cell, null)
	tiles.clear()
	_archive.clear()
	queue.clear()
