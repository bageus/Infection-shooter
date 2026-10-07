extends RefCounted

const ROOT := "res://models/objects/textures/blood_decals_45"
const CATEGORIES := ["splatter", "stain", "smear", "pool", "drops"]
# Each category is one atlas of evenly sized cells, read row by row; the
# frame's 1-based position is its variant ("pool_03" is the third cell).
const ATLASES := {
	"splatter": {"file": "splatter/splatter_atlas_3x3.png", "grid": Vector2i(3, 3)},
	"stain": {"file": "stain/stain_atlas_3x3.png", "grid": Vector2i(3, 3)},
	"smear": {"file": "smear/smear_atlas_3x3.png", "grid": Vector2i(3, 3)},
	"pool": {"file": "pool/pool_atlas_4x2.png", "grid": Vector2i(4, 2)},
	"drops": {"file": "drops/drops_atlas_3x3.png", "grid": Vector2i(3, 3)},
}
# The atlases carry faint alpha noise around each mark; cells are trimmed to
# pixels above this alpha after box-averaging, so noise does not widen them.
const TRIM_ALPHA := 6.0 / 255.0
const TRIM_SHRINKS := 4
# tools/build_blood_atlases.gd cuts the full-size sheets in source/ into
# BUILT_CELL slots; cells.json holds each frame's used size in its slot.
const BUILT_CELL := 512
const CELLS_FILE := "cells.json"
var entries: Dictionary = {}
var recent: Dictionary = {}


# Processed textures are shared by every library with the same settings, so
# restarts and planner decals do not decode and slice the atlases again.
static var _shared: Dictionary = {}


static func frame_count(category: String) -> int:
	var grid: Vector2i = ATLASES[category]["grid"] if ATLASES.has(category) else Vector2i.ZERO
	return grid.x * grid.y


func load_assets(max_dimension: int = 512, brightness: float = 1.18) -> void:
	if not entries.is_empty():
		return
	var key := "%d|%.3f" % [max_dimension, brightness]
	if _shared.has(key):
		entries = _shared[key]
		return
	_shared[key] = entries
	var cells := _built_cells()
	for category in CATEGORIES:
		entries[category] = []
		var path := ROOT.path_join(ATLASES[category]["file"])
		var atlas := _load_image(path)
		if atlas == null:
			continue
		var grid: Vector2i = ATLASES[category]["grid"]
		@warning_ignore("integer_division")
		var cell := Vector2i(atlas.get_width() / grid.x, atlas.get_height() / grid.y)
		var built: Array = cells.get(category, [])
		for index in grid.x * grid.y:
			@warning_ignore("integer_division")
			var origin := Vector2i(index % grid.x, index / grid.x) * cell
			var used: Rect2i
			if built.size() == grid.x * grid.y:
				used = Rect2i(origin, Vector2i(int(built[index][0]), int(built[index][1])))
			else:
				used = _visible_rect(atlas.get_region(Rect2i(origin, cell)))
				used.position += origin
			if not used.has_area():
				continue
			var image := atlas.get_region(used)
			var longest := maxi(image.get_width(), image.get_height())
			if longest > max_dimension:
				var factor := float(max_dimension) / longest
				image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
			image.adjust_bcs(brightness, 1.0, 1.0)
			image.generate_mipmaps()
			entries[category].append({"texture": ImageTexture.create_from_image(image), "aspect": float(used.size.x) / used.size.y, "variant": index + 1})


static func _built_cells() -> Dictionary:
	var path := ROOT.path_join(CELLS_FILE)
	var json := load(path) as JSON if ResourceLoader.exists(path) else null
	return json.data if json != null and json.data is Dictionary else {}


func _load_image(path: String) -> Image:
	var image: Image
	if ResourceLoader.exists(path):
		# The atlases import as Image, so nothing is uploaded to the GPU here.
		var imported: Resource = load(path)
		if imported is Image:
			image = (imported as Image).duplicate() as Image
		elif imported is Texture2D:
			image = (imported as Texture2D).get_image()
	if image == null:
		image = Image.load_from_file(path)
	if image == null or image.is_empty():
		push_warning("Blood atlas unavailable: " + path)
		return null
	if image.is_compressed() and image.decompress() != OK:
		push_warning("Blood atlas could not be decompressed: " + path)
		return null
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	return image


# Visible rectangle of one cell, found on a box-averaged copy so isolated
# near-transparent pixels are ignored; two coarse pixels of margin keep the
# outermost droplets.
static func _visible_rect(image: Image) -> Rect2i:
	var coarse := image.duplicate() as Image
	var scale := 1
	for i in TRIM_SHRINKS:
		if coarse.get_width() < 2 or coarse.get_height() < 2:
			break
		coarse.shrink_x2()
		scale *= 2
	var low := Vector2i(coarse.get_width(), coarse.get_height())
	var high := Vector2i(-1, -1)
	for y in coarse.get_height():
		for x in coarse.get_width():
			if coarse.get_pixel(x, y).a > TRIM_ALPHA:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	if high.x < 0:
		return Rect2i()
	var start := (low - Vector2i(2, 2)) * scale
	var end := (high + Vector2i(3, 3)) * scale
	return Rect2i(Vector2i.ZERO, image.get_size()).intersection(Rect2i(start, end - start))


func choose(category: String) -> Dictionary:
	var options: Array = entries.get(category, [])
	if options.is_empty():
		return {}
	var previous: Array = recent.get(category, [])
	var eligible: Array = []
	for entry in options:
		if not previous.has(entry["variant"]):
			eligible.append(entry)
	if eligible.is_empty():
		eligible = options
	var selected: Dictionary = eligible.pick_random()
	previous.append(selected["variant"])
	if previous.size() > 2:
		previous.pop_front()
	recent[category] = previous
	return selected
