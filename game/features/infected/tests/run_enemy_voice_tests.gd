extends SceneTree
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const REVENANT := preload("res://game/features/infected/public/infected_revenant.tscn")
const PROFILE := preload("res://game/features/infected/enemy_voice_profile.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_profiles()
	await _species_hooks()
	var stage := Node3D.new()
	root.add_child(stage)
	var hunger := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(hunger)
	hunger.set_physics_process(false)
	var target := Node3D.new()
	stage.add_child(target)
	hunger.call("watch_target", target)
	var audio: Node = hunger.get("audio")
	hunger.call("_idle_flavor", false)
	_check(float(hunger.get("_busy")) > 0 and hunger.get("_animation") != null, "Agony really starts an animation")
	_check(_event(audio) == "hunger_agony", "The agony scream begins with Agonize")
	audio.call("stop_voice")
	await process_frame
	hunger.call("_idle_flavor", true)
	_check(_event(audio) in ["hunger_voice"] and not hunger.call("is_alerted"), "Idle scream is not an aggression transition")
	audio.call("stop_voice")
	await process_frame
	audio.call("feeding_tick", .1, false)
	_check(_event(audio).is_empty(), "BiteDown does not play chewing before it reaches the corpse")
	audio.call("feeding_tick", .1, true)
	_check(_event(audio) == "hunger_feeding", "Chewing uses the new feeding recording")
	var voice := audio.get("_vocal") as AudioStreamPlayer3D
	_check(voice != null and voice.bus == &"SFX" and voice.max_distance == 20.0 and voice.unit_size == 2.5 and voice.volume_db >= 3.0, "Feeding is loud, positional and attenuates with distance")
	var original := voice
	audio.call("feeding_tick", .1, true)
	_check(audio.get("_vocal") == original, "Chewing does not stack on every physics frame")
	hunger.call("_end_feeding", false)
	_check(_event(audio).is_empty(), "Standing or aggro interrupts chewing")
	await process_frame
	hunger.set("_feeding", true)
	hunger.call("_on_aggro")
	_check(not hunger.call("is_feeding") and _event(audio) in ["hunger_alert"], "Interrupting a meal does not cut off the new alert shout")
	audio.call("stop_voice")
	await process_frame
	hunger.set("posture", 1)
	audio.call("growl")
	_check(_event(audio) in ["hunger_fours_voice", "hunger_voice"], "On all fours, hunger uses the appropriate voice group")
	audio.call("died")
	_check(_event(audio).is_empty(), "Death stops the old vocal")
	var revenant := REVENANT.instantiate() as CharacterBody3D
	stage.add_child(revenant)
	revenant.set_physics_process(false)
	var other: Node = revenant.get("audio")
	other.call("growl")
	_check(_event(other) in ["revenant_voice", "growl_revenant"], "Revenant never uses Hunger recordings")
	stage.queue_free()
	await process_frame
	await process_frame
	_check(SFX._voices == 0, "Enemy vocal lifetimes end with the actors")
	print("Enemy voice tests: %d failures" % failures)
	quit(failures)


func _species_hooks() -> void:
	var script := preload("res://game/features/infected/infected_audio.gd")
	var fixture := preload("res://game/features/infected/tests/voice_test_body.gd")
	var expected := {
		&"growl_hunger": [&"hunger_idle", &"hunger_death", &"hunger_attack"],
		&"growl_revenant": [&"revenant_idle", &"revenant_death", &"revenant_attack"],
		&"growl_colossus": [&"colossus_idle", &"heavy_death", &"colossus_attack"],
		&"growl_titan": [&"titan_idle", &"heavy_death", &"titan_attack"],
		&"growl_horde": [&"horde_idle", &"enemy_death", &"growl_horde"],
	}
	for species: StringName in expected:
		var body := fixture.new()
		body.growl_sound = species
		root.add_child(body)
		var audio := script.new()
		body.add_child(audio)
		audio.setup(body, 1.0)
		seed(42)
		for i in 30:
			audio._growl_wait = 0.0
			body.alerted = false
			audio.tick(.01, false, true)
			if not _event(audio).is_empty(): break
		_check(_event(audio) == str(expected[species][0]), "Unaware species uses its idle: " + str(species))
		audio.died()
		_check(body.get_children().any(func(n: Node) -> bool: return n.is_in_group("sfx_"+str(expected[species][1]))), "Species death is wired: " + str(species))
		_check(_event(audio).is_empty(), "Death interrupts idle speech")
		body.queue_free()
		await process_frame
		_check(expected[species][2] in PROFILE.PROFILES[species][&"attack"][1], "Species attack is wired")
	_check(not SFX.has_event(&"scream_zombie") and not SFX.has_event(&"roar_heavy"), "Deleted shared vocal events cannot be selected")
	_check(&"colossus_voice" in PROFILE.PROFILES[&"growl_colossus"][&"voice"][1], "Fourth roar is ordinary Colossus speech")


func _profiles() -> void:
	for species in PROFILE.PROFILES:
		for action in PROFILE.PROFILES[species]:
			var spec: Array = PROFILE.PROFILES[species][action]
			var selected: StringName = PROFILE.event_for(species, action, 0.0)
			_check(selected in spec[1], "A real recording is selected for " + str(action))
			if spec[0] < 1.0:
				_check(PROFILE.event_for(species, action, .999).is_empty(), "Optional vocal can be skipped")
			for event in spec[1]:
				_check(SFX.has_event(event), "Every profile event exists: " + str(event))
	var choices := {}
	seed(41)
	for i in 200:
		choices[PROFILE.event_for(&"growl_hunger", &"attack", 0.0)] = true
	_check(choices.has(&"hunger_attack") and choices.has(&"growl_hunger"), "Repeated attacks vary between real groups")


func _event(audio: Node) -> String:
	var voice := audio.get("_vocal") as AudioStreamPlayer3D
	return str(voice.name).trim_prefix("Sfx_") if is_instance_valid(voice) and not voice.is_queued_for_deletion() else ""


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
