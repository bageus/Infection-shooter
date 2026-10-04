extends SceneTree
## Sound catalogue checks (ADR-0018): every event has its processed files,
## playback places a positioned voice and voice limits hold.

const SFX := preload("res://game/core/audio/public/sound_events.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var missing := []
	for event: StringName in SFX.EVENTS:
		var spec: Array = SFX.EVENTS[event]
		for index in range(1, int(spec[SFX.VARIANTS]) + 1):
			var path := SFX.ROOT + "%s/%s_%d.ogg" % [event, event, index]
			var stream := load(path) as AudioStream if ResourceLoader.exists(path) else null
			if stream == null or stream.get_length() < 0.03 or stream.get_length() > 3.6:
				missing.append(path)
	_expect(missing.is_empty(), "Every sound event has its processed variants: %s" % [missing])
	_expect(SFX.EVENTS.size() >= 60, "The catalogue covers weapons, impacts, enemies, doors and items.")
	_expect(AudioServer.get_bus_index(&"SFX") >= 0, "The SFX bus with room reverb exists.")
	var voice := SFX.play(stage, &"pistol_fire", Vector3(3, 1, 2))
	_expect(voice != null and voice.global_position.is_equal_approx(Vector3(3, 1, 2)), "A sound plays where it happened.")
	_expect(voice != null and voice.bus == &"SFX", "Effects route through the SFX bus.")
	_expect(voice != null and voice.pitch_scale > 0.9 and voice.pitch_scale < 1.1, "Pitch varies only slightly.")
	_expect(SFX.play(stage, &"no_such_event") == null, "Unknown events are ignored.")
	var played := 0
	for i in 10:
		if SFX.play(stage, &"elevator_open") != null:
			played += 1
	_expect(played == 1, "Per-event voice limits stop pile-ups (%d)." % played)
	stage.queue_free()
	await process_frame
	print("Sound event tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
