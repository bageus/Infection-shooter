extends RefCounted
## Save-time CPU rasterizer. Source cells stay editable; only sparse pages render in play.
const ATLAS := preload("res://game/presentation/office_floor/biomass_atlas.gd")
const FORMAT := preload("res://game/presentation/office_floor/biomass_bake_format.gd")
const PPU := FORMAT.PIXELS / FORMAT.METERS
var pages: Dictionary = {}
var exclusions: Array[Rect2] = []


func build(records: Array, bounds: Rect2, height: float, tree: SceneTree, alive: Callable, progress: Callable, lighting: Callable = Callable()) -> Dictionary:
	pages.clear()
	var source := ATLAS.albedo_texture().get_image()
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	for index in records.size():
		var record: Dictionary = records[index]
		if not eligible(record): continue
		progress.call("BAKING FLOOR BIOMASS | %d / %d" % [index + 1, records.size()])
		var frame := _frame(record)
		var area := _area(frame).intersection(bounds)
		if area.has_area() and not await _stamp(source, record, frame, area, tree, alive):
			return {"error": "floor bake cancelled or exceeds 64 pages (128 MiB CPU + GPU)"}
	var result := {"version": 1, "y": height, "pages": []}
	for cell: Vector2i in pages:
		if not alive.call(): return {"error": "floor bake cancelled"}
		var tile: Image = pages[cell]
		if lighting.is_valid():
			progress.call("BAKING BIOMASS LIGHT | %d / %d" % [result.pages.size() + 1, pages.size()])
			var lightmap: Image = await lighting.call(cell, height)
			if lightmap == null: return {"error": "lighting bake cancelled"}
			await _shade(tile, lightmap, tree, alive)
			if not alive.call(): return {"error": "floor bake cancelled"}
		result.pages.append({"x": cell.x, "z": cell.y, "png": Marshalls.raw_to_base64(tile.save_png_to_buffer())})
		await tree.process_frame
	pages.clear()
	return result if alive.call() else {"error": "floor bake cancelled"}


static func eligible(record: Dictionary) -> bool:
	return ATLAS.is_biomass_id(str(record.get("blood_texture", ""))) and str(record.get("blood_surface", "floor")) == "floor" and str((record.get("blood_attachment", {}) as Dictionary).get("owner", "")).is_empty() and absf(float(record.get("rotation_x", 0.0))) < 0.01 and absf(float(record.get("rotation_z", 0.0))) < 0.01


static func _frame(record: Dictionary) -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(float(record.get("rotation_y", 0.0))))
	basis = basis.scaled(Vector3(float(record.get("scale_x", 1.0)), 1.0, float(record.get("scale_z", 1.0))))
	return Transform3D(basis, Vector3(float(record.get("x", 0.0)), 0.0, float(record.get("z", 0.0))))


static func _area(frame: Transform3D) -> Rect2:
	var extent := (Vector2(absf(frame.basis.x.x), absf(frame.basis.x.z)) * ATLAS.FOOTPRINT.x + Vector2(absf(frame.basis.z.x), absf(frame.basis.z.z)) * ATLAS.FOOTPRINT.y) * 0.5
	return Rect2(Vector2(frame.origin.x, frame.origin.z) - extent, extent * 2.0)


func _stamp(source: Image, record: Dictionary, frame: Transform3D, area: Rect2, tree: SceneTree, alive: Callable) -> bool:
	var low := Vector2i((area.position * PPU).floor())
	var high := Vector2i((area.end * PPU).ceil())
	var inverse := frame.affine_inverse()
	var origin := ATLAS.cell_origin(ATLAS.cell_of(str(record.blood_texture)))
	for z in range(low.y, high.y):
		for x in range(low.x, high.x):
			var point := Vector2((x + 0.5) / PPU, (z + 0.5) / PPU)
			if _excluded(point): continue
			var local := inverse * Vector3(point.x, 0.0, point.y)
			var uv := Vector2(local.x / ATLAS.FOOTPRINT.x + 0.5, 0.5 + local.z / ATLAS.FOOTPRINT.y)
			if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0: continue
			var color := source.get_pixelv(origin + Vector2i(uv * Vector2(ATLAS.CELL)))
			if color.a < 0.004: continue
			var cell := Vector2i(floori(float(x) / FORMAT.PIXELS), floori(float(z) / FORMAT.PIXELS))
			if not pages.has(cell):
				if pages.size() >= FORMAT.MAX_PAGES: return false
				pages[cell] = Image.create(FORMAT.PIXELS, FORMAT.PIXELS, false, Image.FORMAT_RGBA8)
			var pixel := Vector2i(posmod(x, FORMAT.PIXELS), posmod(z, FORMAT.PIXELS))
			var tile: Image = pages[cell]
			tile.set_pixelv(pixel, tile.get_pixelv(pixel).blend(color))
		if posmod(z, 16) == 0:
			await tree.process_frame
			if not alive.call(): return false
	return true


static func _shade(tile: Image, lightmap: Image, tree: SceneTree, alive: Callable) -> void:
	lightmap.resize(FORMAT.PIXELS, FORMAT.PIXELS, Image.INTERPOLATE_BILINEAR)
	for y in FORMAT.PIXELS:
		for x in FORMAT.PIXELS:
			var pixel := tile.get_pixel(x, y)
			if pixel.a <= 0.0: continue
			var light := lightmap.get_pixel(x, y)
			tile.set_pixel(x, y, Color(pixel.r * light.r, pixel.g * light.g, pixel.b * light.b, pixel.a))
		if y % 16 == 0:
			await tree.process_frame
			if not alive.call(): return


func _excluded(point: Vector2) -> bool:
	for opening in exclusions:
		if opening.has_point(point): return true
	return false
