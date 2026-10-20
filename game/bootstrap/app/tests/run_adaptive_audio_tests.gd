extends SceneTree
## Music transitions, real menu lifecycle, mute independence and old preferences.
const MUSIC := preload("res://game/bootstrap/app/mission_music.gd")
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0

class Enemy:
	extends Node
	var alerted := false
	func is_alerted() -> bool: return alerted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _mission()
	await _completion_handoff()
	await _menu()
	print("Adaptive audio tests: %d failures" % failures)
	quit(failures)


func _mission() -> void:
	var scene := Node.new()
	root.add_child(scene)
	var music := MUSIC.new()
	scene.add_child(music)
	music.set_process(false)
	_check(music.state == &"calm", "Mission starts in active Server Oper")
	_check(MUSIC.CALM.loop and MUSIC.CALM.get_length() > 30, "Calm active region loops")
	_check(MUSIC.THREAT.loop and is_equal_approx(MUSIC.THREAT.loop_offset, 30.08), "Threat intro is skipped on subsequent loop cycles")
	_check(MUSIC.HUNT.loop, "Hunt retains its processed loop")
	music.update_aggression(10, 10.0)
	_check(music.state == &"calm", "Ten aggressors without a player hit do not start Threat")
	music.notify_monster_hit()
	_check(music.state == &"threat", "A confirmed monster hit starts Threat")
	_check(float(music.mixer.current.get_meta(&"start_offset")) == 0.0, "The first Threat starts with its full intro")
	music.mixer._fade.custom_step(4.1)
	_check(music.mixer.current.stream == MUSIC.THREAT, "Threat is the selected recording")
	var enemies: Array[Enemy] = []
	for i in 12:
		var enemy := Enemy.new()
		scene.add_child(enemy)
		enemy.add_to_group(&"infected_alive")
		enemy.alerted = i < 10
		enemies.append(enemy)
	music._process(0.3)
	_check(music.aggression == 10 and music.state == &"threat", "Only actual aggressors count")
	enemies[10].alerted = true
	music._process(0.3)
	_check(music.state == &"hunt", "Eleven simultaneous aggressors start Hunt")
	music.mixer._fade.custom_step(4.1)
	music.update_aggression(10, 0.25)
	_check(music.state == &"hunt", "Exactly ten retains Hunt without threshold chatter")
	music.update_aggression(9, 0.25)
	_check(music.state == &"threat", "Below ten crossfades back to Threat")
	_check(is_equal_approx(float(music.mixer.current.get_meta(&"start_offset")), 30.08), "Ongoing combat does not replay the Threat intro")
	music.mixer._fade.custom_step(4.1)
	music.update_aggression(0, 2.0)
	_check(music.state == &"threat", "Brief quiet does not cut combat")
	music.update_aggression(0, 1.1)
	_check(music.state == &"calm", "Sustained quiet returns to active Server Oper")
	# Reverse a transition mid-fade; the current gain must be continuous.
	music.mixer._fade.custom_step(1.0)
	var outgoing: AudioStreamPlayer = music.mixer.current
	var old_gain: float = outgoing.volume_linear
	music.notify_monster_hit()
	_check(is_equal_approx(outgoing.volume_linear, old_gain), "Interrupting a fade preserves the exact outgoing gain")
	_check(is_finite(old_gain) and music.state == &"threat", "Renewed combat interrupts the outgoing fade safely")
	_check(music.mixer._voices.size() <= 3, "Rapid state changes retain a bounded decoder budget")
	music.mixer._fade.custom_step(4.1)
	if music.mixer._silent:
		var loop_voice: AudioStreamPlayer = music.mixer.current
		loop_voice.set_meta(&"elapsed", MUSIC.THREAT.get_length() - 1.0)
		music.mixer._process(0.0)
		_check(music.mixer.current != loop_voice and is_equal_approx(float(music.mixer.current.get_meta(&"start_offset")), 30.08), "Loop overlap starts only the Threat body before its tail ends")
		music.mixer._fade.custom_step(4.1)
	paused = true
	var volume: float = music.mixer.current.volume_linear
	await create_timer(.15, true).timeout
	_check(is_equal_approx(volume, music.mixer.current.volume_linear), "Gameplay fades pause with gameplay")
	paused = false
	music.finish_mission()
	music.update_aggression(20, 10.0)
	_check(music.state == &"complete", "Completion suppresses further combat music selection")
	music.mixer._fade.custom_step(4.1)
	scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(.1).timeout


func _completion_handoff() -> void:
	var hold := preload("res://game/bootstrap/app/completion_music.gd").new()
	root.add_child(hold)
	hold.set_process(false)
	_check(absf(hold.HOLD.get_length() - 56.0) < .01, "Completion recording is exactly 56 seconds")
	var voice: AudioStreamPlayer = hold.mixer.current
	var voice_id := voice.get_instance_id()
	var old := Node3D.new()
	root.add_child(old)
	current_scene = old
	hold.age = 12.0
	preload("res://game/bootstrap/app/menu/music_navigation.gd").show_main(self, old, hold)
	await process_frame
	var front := current_scene
	var menu: Control = front.get_node("Menu")
	var track: AudioStreamPlayer = menu.get("_music")
	_check(hold.mixer.current.get_instance_id() == voice_id and is_equal_approx(hold.age, 12.0), "Changing to main keeps the same playback instance and cursor")
	_check(not bool(track.get("active")), "Main menu music waits for the completion recording")
	hold._process(44.1)
	await process_frame
	_check(bool(track.get("active")) and track.stream == preload("res://assets/audio/music/main_menu.ogg"), "Main music starts only after Hold finishes")
	_check(is_finite(track.volume_linear), "Completion-to-main fade never interpolates infinite decibels")
	front.queue_free()
	await process_frame
	await process_frame
	# The loader retains this exact root-owned voice while the previous scene is freed.
	var loading_hold := preload("res://game/bootstrap/app/completion_music.gd").new()
	root.add_child(loading_hold)
	loading_hold.set_process(false)
	loading_hold.to_loading()
	loading_hold._process(53.0)
	_check(loading_hold.mode == &"loading" and loading_hold.age < 52.0, "Long loading overlaps another Hold cycle without silence")
	var loader := preload("res://game/bootstrap/app/menu/mission_loader.gd").new()
	root.add_child(loader)
	loader.completion_music = loading_hold
	loader.set("_released_previous", true)
	current_scene = null
	loader.call("_close_error")
	await process_frame
	_check(is_instance_valid(loading_hold) and loading_hold.mode == &"main", "Loading failure hands the live voice to main instead of orphaning it")
	current_scene.queue_free()
	loading_hold.dispose()
	current_scene = null
	await process_frame
	await process_frame
	var released := preload("res://game/bootstrap/app/completion_music.gd").new()
	root.add_child(released)
	released.set_process(false)
	released.to_loading()
	released.release_to_mission()
	_check(released.mode == &"closing", "A ready mission fades out the carried recording")
	released.mixer._fade.custom_step(4.1)
	released._process(4.1)
	await process_frame
	_check(not is_instance_valid(released), "No completion voice survives successful mission activation")
	await create_timer(.1).timeout


func _menu() -> void:
	var had := FileAccess.file_exists(PREFS.FILE)
	var saved := FileAccess.get_file_as_bytes(PREFS.FILE) if had else PackedByteArray()
	# An older config lacks both new keys, which must keep their defaults.
	var old := ConfigFile.new()
	old.set_value("interface_v1", "music_volume", 0.0)
	old.save(PREFS.FILE)
	var prefs := PREFS.new()
	prefs.load_settings()
	_check(prefs.values.menu_music and prefs.values.menu_music_volume == 1.0, "Old settings keep menu music enabled")
	var front := FRONT.instantiate()
	root.add_child(front)
	current_scene = front
	var menu: Control = front.get_node("Menu")
	var track: AudioStreamPlayer = menu.get("_music")
	_check_menu_controls(menu)
	_check(not bool(track.get("active")), "Main music does not start on the first frame")
	await create_timer(.3).timeout
	_check(not bool(track.get("active")), "Main music still waits after 0.3 seconds")
	await create_timer(.8).timeout
	_check(bool(track.get("active")) and track.stream.loop and (DisplayServer.get_name() == "headless" or track.playing), "Main music starts after one second and loops")
	var position := track.get_playback_position()
	menu.refresh()
	_check(bool(track.get("active")) and track.get_playback_position() >= position, "Rebuilding settings does not restart music")
	menu.show_screen("pause")
	_check(bool(track.get("active")) and track.stream.get_length() < 59.0, "Pause selects the trimmed loop immediately")
	paused = true
	await process_frame
	_check(bool(track.get("active")) and not track.stream_paused, "Menu music continues during gameplay pause")
	prefs.values.music_volume = 0.0
	prefs.values.menu_music_volume = .35
	prefs.apply_to_game(self)
	var bus := AudioServer.get_bus_index(&"MenuMusic")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")) and not AudioServer.is_bus_mute(bus), "Menu and gameplay volume are independent")
	_check(absf(AudioServer.get_bus_volume_linear(bus)-.35) < .001, "Menu volume applies live")
	prefs.values.menu_music = false
	prefs.save_settings()
	prefs.apply_to_game(self)
	var reloaded := PREFS.new()
	reloaded.load_settings()
	_check(not reloaded.values.menu_music and AudioServer.is_bus_mute(bus), "Menu switch persists and mutes the menu bus")
	menu.hide()
	_check(not bool(track.get("active")) and not track.playing, "Closing a menu stops its track")
	menu.show_screen("main")
	menu.hide()
	await create_timer(1.1, true).timeout
	_check(not bool(track.get("active")) and not track.playing, "Leaving before the main delay cannot start a stale track")
	paused = false
	front.queue_free()
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	if had:
		FileAccess.open(PREFS.FILE, FileAccess.WRITE).store_buffer(saved)
	else:
		DirAccess.remove_absolute(PREFS.FILE)
	var restore := PREFS.new()
	restore.load_settings()
	restore.apply_to_game(self)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _check_menu_controls(menu: Control) -> void:
	menu.call("activate", "settings")
	var dialog: Control = menu.get("modal")
	var audio_page: Node = dialog.get("settings").tabs.get_child(3)
	var toggle := audio_page.find_child("MenuMusicToggle", true, false) as CheckButton
	var slider := audio_page.find_child("MenuMusicVolume", true, false) as HSlider
	_check(toggle != null and slider != null, "Both menu music controls exist in Audio settings")
	if toggle != null and slider != null:
		toggle.set_pressed(false)
		var preferences := PREFS.new()
		preferences.load_settings()
		_check(not preferences.values.menu_music, "The actual menu toggle saves its setting")
		toggle.set_pressed(true)
		slider.value = .4
		preferences.load_settings()
		_check(is_equal_approx(preferences.values.menu_music_volume, .4), "The actual menu slider saves its setting")
	menu.call("close_dialog")
