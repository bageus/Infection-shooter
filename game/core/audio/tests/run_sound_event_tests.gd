extends SceneTree
## Sound catalogue checks (ADR-0018): every event has its processed files,
## playback places a positioned voice and voice limits hold.

const SFX := preload("res://game/core/audio/public/sound_events.gd")

## Beds that run for a whole skill effect (storm field, acid pool, blade orbit).
const LASTING := [&"extinguisher_spray", &"skill_storm_field", &"acid_sizzle", &"bone_blades_whirl"]

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
			var longest := 6.5 if event in LASTING else 3.6
			if stream == null or stream.get_length() < 0.03 or stream.get_length() > longest:
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
	_test_ui(stage)
	stage.queue_free()
	await process_frame
	_expect(SFX._voices == 0 and int(SFX._per_event.get(&"elevator_open", 0)) == 0, "Voice counts return to zero when sounds end (%d)." % SFX._voices)
	print("Sound event tests: %d failure(s)." % failures)
	quit(failures)


func _test_ui(stage: Node) -> void:
	for event: StringName in SFX.UI_EVENTS:
		var stream: AudioStreamWAV = SFX.UI_EVENTS[event][0]
		_expect(stream.get_length() > 0.03 and stream.get_length() < 0.5 and not stream.data.is_empty(), "UI cue contains short PCM: " + String(event))
		_expect(SFX.has_event(event), "Interface cue is discoverable: " + String(event))
	_expect(SFX.play_ui(stage, &"missing") == null, "Unknown UI events are ignored")
	_expect(SFX.play_ui(null, &"menu_hover") == null, "UI playback rejects missing owners")
	var count := 0
	for i in 8:
		if SFX.play_ui(stage, &"menu_hover") != null:
			count += 1
	_expect(count == 3, "Rapid hover has a per-event limit")
	for event in [&"mutation_hover", &"mutation_click", &"mutation_lock"]:
		for i in 3:
			SFX.play_ui(stage, event)
	_expect(get_node_count_in_group(SFX.UI_GROUP) == SFX.UI_MAX_VOICES, "UI has a separate eight-voice budget")
	_expect(SFX.play_ui(stage, &"mutation_unlock") == null, "UI budget prevents unbounded overlap")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
