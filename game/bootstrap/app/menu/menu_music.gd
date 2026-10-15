extends AudioStreamPlayer
## Menu-owned dry music; the screen can rebuild without restarting its track.

const MAIN := preload("res://assets/audio/music/main_menu.ogg")
const PAUSE := preload("res://assets/audio/music/menu_from_game.ogg")
var screen: Control
var _delay: Timer
var _kind := ""


func setup(owner_screen: Control) -> void:
	screen = owner_screen
	name = "MenuMusic"
	bus = &"MenuMusic"
	volume_db = -9.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_delay = Timer.new()
	_delay.one_shot = true
	_delay.wait_time = 1.0
	add_child(_delay)
	_delay.timeout.connect(_start)
	screen.visibility_changed.connect(sync)
	sync()


func sync() -> void:
	if not screen.is_visible_in_tree():
		_delay.stop()
		stop()
		_kind = ""
		return
	var kind := str(screen.get("screen_kind"))
	if kind == _kind:
		return
	_kind = kind
	stop()
	_delay.stop()
	stream = MAIN if kind == "main" else PAUSE
	if kind == "main":
		_delay.start()
	else:
		_start()


func _start() -> void:
	if is_instance_valid(screen) and screen.is_visible_in_tree():
		play()
