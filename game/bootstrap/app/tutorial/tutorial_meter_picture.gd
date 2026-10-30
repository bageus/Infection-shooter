extends Control
## Little picture of the mutation scale for the tutorial: fill so far and a bright control-loss marker.

const PALETTE := preload("res://game/bootstrap/app/tutorial/tutorial_palette.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")

var mutation := 0.0
var threshold := 30.0


func _init() -> void:
	custom_minimum_size = Vector2(420, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var bar := Rect2(0, 26, size.x, 16)
	draw_rect(bar, PALETTE.TRACK)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(mutation / 100.0, 0.0, 1.0), bar.size.y)), PALETTE.MUTATION)
	draw_rect(bar, PALETTE.BORDER, false, 1.0)
	var x := bar.size.x * clampf(threshold / 100.0, 0.0, 1.0)
	draw_rect(Rect2(x - 9, bar.position.y - 8, 18, bar.size.y + 16), Color(PALETTE.CRITICAL, 0.3))
	draw_rect(Rect2(x - 2, bar.position.y - 12, 4, bar.size.y + 24), PALETTE.CRITICAL)
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, 14), TEXT.t("hudMutation"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PALETTE.MUTED)
	draw_string(font, Vector2(x - 20, 62), str(roundi(threshold)), HORIZONTAL_ALIGNMENT_CENTER, 40, 14, PALETTE.CRITICAL)
