extends Node
## Mission-local music presentation. Reads the public perception query at 4 Hz.
## Brief changes near the threshold do not repeatedly trigger the ending sting.

const CALM := [preload("res://assets/audio/music/server_oper.ogg"), preload("res://assets/audio/music/seamless_loop.ogg")]
const COMBAT := preload("res://assets/audio/music/tower_hunt.ogg")
const BOOM := preload("res://assets/audio/music/music_cinematic_boom.ogg")
const FADE_SECONDS := 2.0
const RELEASE_SECONDS := 3.0
const LEVEL := 0.32
var state := &"calm"
var aggression := 0
var _calm_index := -1
var _quiet_time := 0.0
var _poll_time := 0.0
var _players: Array[AudioStreamPlayer] = []
var _current := 0
var _fade: Tween
var _sting: AudioStreamPlayer


func _ready() -> void:
	name = "MissionMusic"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Track" + str(i)
		player.bus = &"Music"
		player.volume_linear = 0.0
		add_child(player)
		_players.append(player)
	_sting = AudioStreamPlayer.new()
	_sting.name = "CombatEnding"
	_sting.bus = &"Music"
	_sting.stream = BOOM
	_sting.volume_linear = LEVEL
	add_child(_sting)
	_sting.finished.connect(_after_boom)
	_start_calm()


func _process(delta: float) -> void:
	_poll_time += delta
	if _poll_time < 0.25:
		return
	var elapsed := _poll_time
	_poll_time = 0.0
	var count := 0
	for enemy in get_tree().get_nodes_in_group(&"infected_alive"):
		if not enemy.is_queued_for_deletion() and enemy.has_method("is_alerted") and bool(enemy.call("is_alerted")):
			count += 1
	update_aggression(count, elapsed)


func update_aggression(count: int, delta: float) -> void:
	aggression = count
	if count > 3:
		_quiet_time = 0.0
		if state != &"combat":
			state = &"combat"
			_sting.stop()
			_crossfade(COMBAT)
		return
	if state != &"combat":
		return
	_quiet_time += delta
	if _quiet_time >= RELEASE_SECONDS:
		_end_combat()


func _crossfade(stream: AudioStream) -> void:
	_cancel_fade()
	var old := _players[_current]
	_current = 1 - _current
	var next := _players[_current]
	next.stop()
	next.stream = stream
	next.volume_linear = 0.0
	next.play()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(old, "volume_linear", 0.0, FADE_SECONDS)
	_fade.tween_property(next, "volume_linear", LEVEL, FADE_SECONDS)
	_fade.chain().tween_callback(old.stop)


func _end_combat() -> void:
	state = &"ending"
	_cancel_fade()
	_fade = create_tween().set_parallel(true)
	for player in _players:
		_fade.tween_property(player, "volume_linear", 0.0, FADE_SECONDS)
	_fade.chain().tween_callback(_play_boom)


func _play_boom() -> void:
	if state != &"ending":
		return
	for player in _players:
		player.stop()
	state = &"boom"
	_sting.play()


func _after_boom() -> void:
	if state == &"boom":
		_start_calm()


func _start_calm() -> void:
	state = &"calm"
	# Random first track; thereafter alternate, so the return is not repetitive.
	_calm_index = randi_range(0, 1) if _calm_index < 0 else 1 - _calm_index
	_crossfade(CALM[_calm_index])


func _cancel_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
