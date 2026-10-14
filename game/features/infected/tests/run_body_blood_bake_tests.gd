extends SceneTree
## Checks for the wound bake (body_blood_bake.gd): a wound paints a blood mask
## on its surface, blood runs down from it, and the mask keeps every wound.

const BAKE := preload("res://game/features/infected/body_blood_bake.gd")

var failures := 0


func _init() -> void:
	_run()


func _run() -> void:
	var surface := _unit_square()
	var mask := BAKE.create_mask()
	_expect(mask.get_width() == BAKE.SIZE and mask.get_format() == Image.FORMAT_RG8, "The mask is a square RG8 image.")
	_expect(BAKE.paint(mask, surface, Vector3(0.5, 0.5, 0.0), 0.1), "A wound on the surface paints something.")
	_expect(_red(mask, 64, 64) > 0.9, "The centre of the wound is blood.")
	_expect(_green(mask, 64, 64) > 0.9, "The centre of the wound is the dark core.")
	_expect(_red(mask, 4, 4) == 0.0, "Far from the wound stays clean.")
	# Image rows run down the surface (row = (1 - rest y) * SIZE), so rows below
	# the wound are lower on the body.
	_expect(_red(mask, 64, 83) > 0.5, "Blood runs down from the wound.")
	_expect(_red(mask, 64, 45) < 0.1, "Nothing spreads far above the wound.")
	var before := mask.duplicate()
	_expect(not BAKE.paint(mask, surface, Vector3(0.5, 0.5, 0.0), 0.1), "Painting the same wound again changes nothing.")
	_expect(mask.get_data() == before.get_data(), "A repeated wound leaves the mask identical.")
	_expect(BAKE.paint(mask, surface, Vector3(0.1, 0.1, 0.0), 0.05), "A second wound paints beside the first.")
	_expect(_red(mask, 64, 64) > 0.9 and _red(mask, 13, 115) > 0.9, "Earlier wounds stay after later ones.")
	_expect(not BAKE.paint(mask, surface, Vector3(5.0, 5.0, 0.0), 0.1), "A wound off the surface paints nothing.")
	_expect(not BAKE.paint(mask, surface, Vector3(0.5, 0.5, 0.0), 0.0), "A zero radius paints nothing.")
	print("Body blood bake tests: %d failure(s)." % failures)
	quit(failures)


# Two triangles covering the unit square in the z=0 plane, with uv.y = 1 - y.
func _unit_square() -> Dictionary:
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)])
	var uvs := PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	return {"vertices": vertices, "uvs": uvs, "indices": PackedInt32Array([0, 1, 2, 0, 2, 3])}


func _red(mask: Image, x: int, y: int) -> float:
	return mask.get_pixel(x, y).r


func _green(mask: Image, x: int, y: int) -> float:
	return mask.get_pixel(x, y).g


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
