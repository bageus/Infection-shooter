extends Control
## Gas mask glyph for the HUD: face plate, two lenses and a filter canister.

const PALETTE := preload("res://game/presentation/prototype_hud/hud_palette.gd")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var ink := PALETTE.INK
	var plate := PackedVector2Array()
	for point in [Vector2(0.12, 0.2), Vector2(0.88, 0.2), Vector2(0.92, 0.55), Vector2(0.7, 0.85), Vector2(0.3, 0.85), Vector2(0.08, 0.55)]:
		plate.append(point * Vector2(w, h))
	draw_colored_polygon(plate, ink)
	for x in [0.3, 0.7]:
		draw_circle(Vector2(x * w, 0.42 * h), 0.13 * minf(w, h), Color(0.07, 0.08, 0.08))
	draw_circle(Vector2(0.5 * w, 0.8 * h), 0.14 * minf(w, h), Color(0.07, 0.08, 0.08))
	draw_arc(Vector2(0.5 * w, 0.8 * h), 0.14 * minf(w, h), 0.0, TAU, 20, ink, 1.5)
