extends SceneTree

const BLOOD_LEVEL := preload("res://game/core/vfx/public/blood_level.gd")
const DECAL_PROP := preload("res://game/presentation/office_floor/blood_decal_prop.gd")
const LIBRARY := preload("res://game/presentation/office_floor/blood_texture_library.gd")
var failures := 0


func _init() -> void:
	_run()


func _run() -> void:
	BLOOD_LEVEL.set_level(9)
	_expect(BLOOD_LEVEL.level == BLOOD_LEVEL.COUNT - 1, "Blood level is clamped to the top step")
	BLOOD_LEVEL.set_level(-1)
	_expect(BLOOD_LEVEL.level == BLOOD_LEVEL.GREEN, "Blood level is clamped to the green step")
	BLOOD_LEVEL.set_level(1)
	_expect(BLOOD_LEVEL.scale_amount(16) == 6 and BLOOD_LEVEL.scale_amount(1) == 1, "Low blood cuts the amount to about a third and keeps at least one drop")
	_expect(is_equal_approx(BLOOD_LEVEL.scale_speed(2.0), 1.6) and not BLOOD_LEVEL.is_green(), "Low blood is red and flies a little closer")
	var per_hit := [BLOOD_LEVEL.scale_amount(5)]
	BLOOD_LEVEL.set_level(2)
	per_hit.append(BLOOD_LEVEL.scale_amount(5))
	_expect(BLOOD_LEVEL.scale_amount(16) == 16 and BLOOD_LEVEL.scale_speed(2.0) == 2.0, "Medium blood keeps the base amount and speed")
	BLOOD_LEVEL.set_level(3)
	per_hit.append(BLOOD_LEVEL.scale_amount(5))
	_expect(BLOOD_LEVEL.scale_speed(2.0) == 3.0 and BLOOD_LEVEL.scale_amount(16) == 22, "Maximum blood is heavier and flies half as far again, not three times")
	_expect(per_hit == [2, 5, 7], "Splatters per hit step clearly from low to medium to maximum: %s" % [per_hit])
	BLOOD_LEVEL.set_level(0)
	_expect(BLOOD_LEVEL.is_green() and BLOOD_LEVEL.color().g > BLOOD_LEVEL.color().r, "Green level colours blood green")
	var green := LIBRARY.new()
	green.call("load_assets", 512, 1.18, true, BLOOD_LEVEL.color())
	var generated: Dictionary = green.get("entries")
	var pixel := _strongest_pixel((generated["splatter"][0] as Dictionary)["texture"] as Texture2D)
	_expect(pixel.g > pixel.r, "Procedural decals take the green colour at the green level")
	BLOOD_LEVEL.force_green()
	BLOOD_LEVEL.set_level(3)
	_expect(BLOOD_LEVEL.is_green() and BLOOD_LEVEL.color() == BLOOD_LEVEL.GREEN_COLOR, "A platform that forces green blood ignores any other level")
	var placed: Dictionary = DECAL_PROP.texture_entry("splatter_01")
	var placed_pixel := _strongest_pixel(placed["texture"] as Texture2D)
	_expect(placed_pixel.g > placed_pixel.r, "Decals placed in a map are green when the platform forces green blood")
	BLOOD_LEVEL.forced_green = false
	BLOOD_LEVEL.set_level(2)
	_expect(DECAL_PROP.texture_entry("splatter_01")["texture"] != placed["texture"], "Placed decals switch back to the atlas once the force is lifted")
	BLOOD_LEVEL.set_level(2)
	_expect(BLOOD_LEVEL.level == 2, "Blood level is free again once the force is lifted")
	print("Blood level tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _strongest_pixel(texture: Texture2D) -> Color:
	var image := texture.get_image()
	var best := Color.TRANSPARENT
	for y in image.get_height():
		for x in image.get_width():
			var candidate := image.get_pixel(x, y)
			if candidate.a > best.a:
				best = candidate
	return best


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
