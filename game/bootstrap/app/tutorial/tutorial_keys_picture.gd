extends Control
## Animated key caps for a lesson. Items: {text, x, y, w} in key units. In "cycle" mode the keys
## are pressed one after another, in "all" mode they are pressed together.

const PALETTE := preload("res://game/bootstrap/app/tutorial/tutorial_palette.gd")
const TITLE_FONT := preload("res://assets/interface/fonts/title.ttf")
const UNIT := 46.0
const GAP := 6.0
const STEP_SECONDS := 0.6

var items: Array = []
var mode := "cycle"


func show_keys(layout: Array, press_mode: String) -> void:
	items = layout
	mode = press_mode
	var size := Vector2.ZERO
	for item: Dictionary in items:
		size.x = maxf(size.x, (float(item["x"]) + float(item.get("w", 1.0))) * UNIT)
		size.y = maxf(size.y, (float(item["y"]) + 1.0) * UNIT)
	custom_minimum_size = size
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var pressed := int(Time.get_ticks_msec() / (STEP_SECONDS * 1000.0)) % maxi(items.size(), 1)
	var offset := (size.x - custom_minimum_size.x) * 0.5
	for index in items.size():
		var item: Dictionary = items[index]
		var down := mode == "all" or index == pressed
		var rect := Rect2(offset + float(item["x"]) * UNIT, float(item["y"]) * UNIT,
				float(item.get("w", 1.0)) * UNIT - GAP, UNIT - GAP)
		if down:
			rect.position.y += 3.0
		var style := StyleBoxFlat.new()
		style.bg_color = PALETTE.KEY_GOLD if down else PALETTE.TRACK
		style.border_color = PALETTE.INK
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		draw_style_box(style, rect)
		var font_size := 15 if str(item["text"]).length() <= 3 else 12
		var text_size := TITLE_FONT.get_string_size(str(item["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(TITLE_FONT, rect.position + Vector2((rect.size.x - text_size.x) * 0.5, (rect.size.y + text_size.y) * 0.5 - 3.0),
				str(item["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK if down else PALETTE.INK)
