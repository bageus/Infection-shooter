extends SceneTree

const ICONS := preload("res://game/presentation/prototype_hud/weapon_icon_regions.gd")
var failures := 0


func _init() -> void:
	var image := Image.create(150, 100, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for index in range(6):
		var column := index % 3
		var row := floori(float(index) / 3.0)
		image.fill_rect(Rect2i(10 + column * 50, 10 + row * 50, 22 + column * 3, 18), Color(0.1, 0.5, 1.0, 1.0))
	image.set_pixel(0, 0, Color.WHITE)
	var source := ImageTexture.create_from_image(image)
	var icons := ICONS.extract(source)
	_expect(icons.size() == 6, "Two-row atlas extracts six icons and ignores a stray pixel.")
	if icons.size() == 6:
		for index in range(6):
			_expect(icons[index].get_width() == 22 + (index % 3) * 3 and icons[index].get_height() == 18, "Transparent padding is removed without stretching artwork.")
	_expect(source.get_width() == 150 and source.get_height() == 100, "Shared source texture is unchanged.")
	print("Weapon icon tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
