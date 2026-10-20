extends AudioStreamPlayer
## Menu-owned dry music; the screen can rebuild without restarting its track.

const MAIN := preload("res://assets/audio/music/main_menu.ogg")
const PAUSE := preload("res://assets/audio/music/menu_from_game.ogg")
var screen: Control
var _delay: Timer
var _kind := ""
var active := false
var completion_music: Node
var _waiting_completion := false
var _fade_in: Tween


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
		active = false
		return
	var kind := str(screen.get("screen_kind"))
	if _waiting_completion or (kind == "complete" and is_instance_valid(completion_music)):
		_delay.stop()
		stop()
		active = false
		return
	if kind == _kind:
		return
	_kind = kind
	active = false
	stop()
	_delay.stop()
	stream = MAIN if kind == "main" else PAUSE
	if kind == "main":
		_delay.start()
	else:
		_start()


func _start() -> void:
	if is_instance_valid(screen) and screen.is_visible_in_tree():
		active = true
		if DisplayServer.get_name() != "headless":
			play()


func _exit_tree() -> void:
	active = false
	_delay.stop()
	stop()
	stream = null


func wait_for_completion(completion: Node) -> void:
	completion_music = completion
	_waiting_completion = true
	_delay.stop()
	stop()
	active = false
	completion.connect("finished", _after_completion, CONNECT_ONE_SHOT)


func _after_completion() -> void:
	_waiting_completion = false
	completion_music = null
	if is_instance_valid(screen) and screen.is_visible_in_tree() and str(screen.get("screen_kind")) == "main":
		_kind = "main"
		stream = MAIN
		volume_linear = 0.0
		_start()
		_fade_in = create_tween()
		_fade_in.tween_property(self, "volume_linear", db_to_linear(-9.0), 4.0)
