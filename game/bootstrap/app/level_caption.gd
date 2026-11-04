extends CanvasLayer
## Centered caption (checkpoint label, level description) that fades out after `seconds`.

const FADE_SECONDS := 0.6

var caption := "Checkpoint"
var seconds := 2.5


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var label := Label.new()
	label.name = "LevelCaption"
	label.text = caption
	label.custom_minimum_size = Vector2(720, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	center.add_child(label)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(seconds)
	tween.tween_property(label, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(queue_free)
