extends Node
## Bounded scene-owned voices. Interrupted fades continue from their audible gains.
const FADE_SECONDS := 4.0
const LEVEL := 0.32
var _voices: Array[AudioStreamPlayer] = []
var current: AudioStreamPlayer
var _fade: Tween
var bus_name: StringName = &"Music"
var _silent := DisplayServer.get_name() == "headless"


func fade_to(stream: AudioStream, offset: float = 0.0, restart: bool = false) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var next: AudioStreamPlayer
	if stream != null and not restart:
		for voice in _voices:
			if voice.stream == stream and (voice.playing or _silent):
				next = voice
				break
	if stream != null and next == null:
		# Only calm/threat/hunt can overlap; completion loops use at most two.
		if _voices.size() >= 3:
			var quietest := _voices[0]
			for voice in _voices:
				if voice.volume_linear < quietest.volume_linear:
					quietest = voice
			_voices.erase(quietest)
			quietest.stop()
			quietest.stream = null
			quietest.queue_free()
		next = AudioStreamPlayer.new()
		next.bus = bus_name
		next.stream = stream
		next.volume_linear = 0.0
		add_child(next)
		_voices.append(next)
		if not _silent:
			next.play(offset)
		next.set_meta(&"start_offset", offset)
	current = next
	var voices := _voices.duplicate()
	var gains: Array[float] = []
	for voice in voices:
		gains.append(voice.volume_linear)
	_fade = create_tween()
	_fade.tween_method(func(progress: float) -> void:
		var weight := smoothstep(0.0, 1.0, progress)
		for index in voices.size():
			var voice: AudioStreamPlayer = voices[index]
			if is_instance_valid(voice):
				var target := LEVEL if voice == next else 0.0
				voice.volume_linear = sqrt(lerpf(gains[index] * gains[index], target * target, weight)),
		0.0, 1.0, FADE_SECONDS)
	_fade.tween_callback(func() -> void:
		for voice in voices:
			if voice != current and is_instance_valid(voice):
				_voices.erase(voice)
				voice.stop()
				voice.stream = null
				voice.queue_free())


func stop_all() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
			voice.queue_free()
	_voices.clear()
	current = null


func _exit_tree() -> void:
	stop_all()
