extends CanvasLayer
## Centered caption that fades out after a level started from "Continue".

const SHOW_SECONDS := 2.5
const FADE_SECONDS := 0.6

var caption := "Checkpoint"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	var label := Label.new()
	label.text = caption
	label.name = "CheckpointCaption"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(label)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(SHOW_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(queue_free)
