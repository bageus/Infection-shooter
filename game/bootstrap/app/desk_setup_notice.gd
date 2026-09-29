extends PanelContainer

var _message: Label
var _timer: Timer


func _ready() -> void:
	name = "DeskSetupNotice"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -215.0
	offset_right = 215.0
	offset_top = 42.0
	offset_bottom = 100.0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.18, 0.07, 0.04, 0.93)
	add_theme_stylebox_override("panel", background)
	_message = Label.new()
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_message)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 5.0
	add_child(_timer)
	_timer.timeout.connect(hide)
	hide()


func show_reason(reason: String) -> void:
	_message.text = reason
	show()
	_timer.start()


func dismiss() -> void:
	_timer.stop()
	hide()
