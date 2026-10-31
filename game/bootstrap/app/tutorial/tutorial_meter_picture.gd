extends Control
## Little picture of the mutation scale for the tutorial: fill so far and a bright control-loss marker.

const PALETTE := preload("res://game/bootstrap/app/tutorial/tutorial_palette.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")

var mutation := 0.0
var threshold := 30.0
var armor := -1.0 # 0..1 when the picture shows the armor bar above the health bar instead


func _init() -> void:
	custom_minimum_size = Vector2(420, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if armor >= 0.0:
		_draw_armor()
		return
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


# Large armor bar stacked above the health bar, as in the HUD.
func _draw_armor() -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, 14), TEXT.t("hudArmor"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PALETTE.ARMOR)
	var plate := Rect2(0, 20, size.x, 18)
	draw_rect(plate, PALETTE.TRACK)
	draw_rect(Rect2(plate.position, Vector2(plate.size.x * clampf(armor, 0.0, 1.0), plate.size.y)), PALETTE.ARMOR)
	draw_rect(plate, PALETTE.BORDER, false, 1.0)
	var health := Rect2(0, 44, size.x, 18)
	draw_rect(health, PALETTE.TRACK)
	draw_rect(Rect2(health.position, Vector2(health.size.x, health.size.y)), PALETTE.HEALTH)
	draw_rect(health, PALETTE.BORDER, false, 1.0)
	draw_string(font, Vector2(4, 58), TEXT.t("hudHealth"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PALETTE.INK)
