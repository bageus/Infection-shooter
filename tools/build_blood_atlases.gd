extends SceneTree
## Pre-cuts the full-size blood atlases into game-sized atlases.
##
##   godot --headless --path . --script res://tools/build_blood_atlases.gd
##
## Reads blood_decals_45/source/<category>_atlas_*.png (not imported by the
## game), trims every cell to its visible marks, shrinks it to at most CELL
## pixels and writes blood_decals_45/<category>/<category>_atlas_*.png with
## one CELL×CELL slot per frame plus cells.json with each frame's used size.
## The game then reads frames directly instead of decoding 6k-pixel sheets.

const LIBRARY := preload("res://game/presentation/office_floor/blood_texture_library.gd")
const CELL := LIBRARY.BUILT_CELL


func _init() -> void:
	var atlas_root := ProjectSettings.globalize_path(LIBRARY.ROOT)
	var cells: Dictionary = {}
	for category: String in LIBRARY.CATEGORIES:
		var file: String = LIBRARY.ATLASES[category]["file"]
		var grid: Vector2i = LIBRARY.ATLASES[category]["grid"]
		var source := Image.load_from_file(atlas_root.path_join("source").path_join(file.get_file()))
		if source == null or source.is_empty():
			push_error("Blood source atlas missing: " + file)
			quit(1)
			return
		source.convert(Image.FORMAT_RGBA8)
		@warning_ignore("integer_division")
		var cell := Vector2i(source.get_width() / grid.x, source.get_height() / grid.y)
		var output := Image.create_empty(grid.x * CELL, grid.y * CELL, false, Image.FORMAT_RGBA8)
		var sizes: Array = []
		for index in grid.x * grid.y:
			@warning_ignore("integer_division")
			var image := source.get_region(Rect2i(Vector2i(index % grid.x, index / grid.x) * cell, cell))
			var used := LIBRARY._visible_rect(image)
			if not used.has_area():
				sizes.append([0, 0])
				continue
			image = image.get_region(used)
			var longest := maxi(image.get_width(), image.get_height())
			if longest > CELL:
				var factor := float(CELL) / longest
				image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
			@warning_ignore("integer_division")
			output.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(index % grid.x, index / grid.x) * CELL)
			sizes.append([image.get_width(), image.get_height()])
		cells[category] = sizes
		var target := atlas_root.path_join(file)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		output.save_png(target)
		print("%s: %s -> %s" % [category, source.get_size(), output.get_size()])
	var json := FileAccess.open(atlas_root.path_join(LIBRARY.CELLS_FILE), FileAccess.WRITE)
	json.store_string(JSON.stringify(cells))
	json.close()
	quit()
