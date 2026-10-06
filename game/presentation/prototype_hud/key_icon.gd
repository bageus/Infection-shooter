extends Control

# Flat emergency-key glyph for the HUD key cell: bow ring, shaft and two teeth,
# drawn to fit the control so it scales with the cell.

@export var color := Color("dcae4a")


func _draw() -> void:
	var unit := minf(size.x / 2.2, size.y)
	var origin := (size - Vector2(unit * 2.2, unit)) * 0.5
	var bow := origin + Vector2(unit * 0.5, unit * 0.5)
	var thickness := maxf(2.0, unit * 0.16)
	draw_arc(bow, unit * 0.36, 0.0, TAU, 32, color, thickness, true)
	var shaft_y := bow.y - thickness * 0.5
	draw_rect(Rect2(bow.x + unit * 0.36, shaft_y, unit * 1.7, thickness), color)
	draw_rect(Rect2(origin.x + unit * 1.62, shaft_y, thickness, unit * 0.36), color)
	draw_rect(Rect2(origin.x + unit * 1.98, shaft_y, thickness, unit * 0.44), color)
