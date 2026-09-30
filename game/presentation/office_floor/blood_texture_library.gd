extends RefCounted

const ROOT := "res://models/objects/textures/blood_decals_45"
const CATEGORIES := ["splatter", "stain", "smear", "pool", "drops"]
var entries: Dictionary = {}
var recent: Dictionary = {}


func load_assets(max_dimension: int = 512) -> void:
	if not entries.is_empty():
		return
	for category in CATEGORIES:
		entries[category] = []
		for index in range(1, 10):
			var path := ROOT.path_join(category).path_join("%s_%02d.png" % [category, index])
			var image: Image
			if ResourceLoader.exists(path):
				var imported := load(path) as Texture2D
				if imported != null:
					image = imported.get_image()
			if image == null:
				image = Image.load_from_file(path)
			if image == null or image.is_empty():
				push_warning("Blood texture unavailable: " + path)
				continue
			if image.is_compressed():
				if image.decompress() != OK:
					push_warning("Blood texture could not be decompressed: " + path)
					continue
			image.convert(Image.FORMAT_RGBA8)
			var used := image.get_used_rect()
			if not used.has_area():
				continue
			image = image.get_region(used)
			var longest := maxi(image.get_width(), image.get_height())
			if longest > max_dimension:
				var factor := float(max_dimension) / longest
				image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
			image.generate_mipmaps()
			entries[category].append({"texture": ImageTexture.create_from_image(image), "aspect": float(used.size.x) / used.size.y, "variant": index})


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
