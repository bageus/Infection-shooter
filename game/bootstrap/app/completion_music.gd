extends Node
## Explicitly handed between bootstrap scene roots; never discovered as a service.
signal finished
const HOLD := preload("res://assets/audio/music/tower_hold.ogg")
const MIX := preload("res://game/bootstrap/app/music_crossfade.gd")
var mode := &"complete"
var age := 0.0
var mixer: MIX
var _closing := 0.0


func _ready() -> void:
	name = "CompletionMusic"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mixer = MIX.new()
	mixer.set("bus_name", &"MenuMusic")
	add_child(mixer)
	mixer.fade_to(HOLD)


func _process(delta: float) -> void:
	if mode == &"closing":
		_closing += delta
		if _closing >= MIX.FADE_SECONDS:
			dispose()
		return
	age += maxf(delta, 0.0)
	if mode == &"main":
		if age >= HOLD.get_length():
			finished.emit()
			dispose()
	elif age >= HOLD.get_length() - MIX.FADE_SECONDS:
		# Completion/loading can last longer than one recording; overlap its tail.
		age = fmod(age, HOLD.get_length() - MIX.FADE_SECONDS)
		mixer.fade_to(HOLD, 0.0, true)


func to_main() -> void:
	mode = &"main"


func to_loading() -> void:
	mode = &"loading"


func release_to_mission() -> void:
	if mode == &"closing":
		return
	mode = &"closing"
	_closing = 0.0
	mixer.fade_to(null)


func dispose() -> void:
	if is_instance_valid(mixer):
		mixer.stop_all()
	queue_free()
