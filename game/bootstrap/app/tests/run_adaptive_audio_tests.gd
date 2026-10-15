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
	await _menu()
	print("Adaptive audio tests: %d failures" % failures)
	quit(failures)


func _mission() -> void:
	var scene := Node.new()
	root.add_child(scene)
	var music := MUSIC.new()
	scene.add_child(music)
	music.set_process(false)
	_check(music.state == &"calm", "Mission starts calm")
	for stream in MUSIC.CALM + [MUSIC.COMBAT]:
		_check(stream.loop and stream.get_length() > 100, "Gameplay music has a long loop")
	_check(not MUSIC.BOOM.loop, "Ending boom is a one-shot")
	music.update_aggression(3, 10.0)
	_check(music.state == &"calm", "Three alerted enemies do not start battle music")
	# The actual poll ignores unaware enemies, rather than counting population.
	var enemies: Array[Enemy] = []
	for i in 9:
		var enemy := Enemy.new()
		scene.add_child(enemy)
		enemy.add_to_group(&"infected_alive")
		enemy.alerted = i < 3
		enemies.append(enemy)
	music._process(0.3)
	_check(music.aggression == 3 and music.state == &"calm", "Population is not aggression")
	enemies[3].alerted = true
	music._process(0.3)
	_check(music.aggression == 4 and music.state == &"combat", "Fourth aggressor fades in Tower Hunt")
	music._fade.custom_step(2.1)
	_check(music._players[music._current].stream == MUSIC.COMBAT, "Combat selects the correct track")
	_check(music._players[1-music._current].volume_linear < 0.001, "Outgoing calm is silent")
	music.update_aggression(2, 2.0)
	_check(music.state == &"combat", "Brief threshold dip retains battle music")
	music.update_aggression(4, 0.1)
	music.update_aggression(0, 2.5)
	_check(music.state == &"combat", "Renewed aggression resets the quiet deadline")
	music.update_aggression(0, 0.6)
	_check(music.state == &"ending", "Sustained quiet starts a gradual ending")
	music._fade.custom_step(2.1)
	_check(music.state == &"boom" and (music._silent or music._sting.playing), "Boom follows the fade")
	music._sting.stop()
	music._sting.finished.emit()
	_check(music.state == &"calm", "Calm resumes only after boom completes")
	music.update_aggression(4, .25)
	music.update_aggression(0, 3.1)
	music.update_aggression(4, .25)
	music._fade.custom_step(3.0)
	_check(music.state == &"combat" and not music._sting.playing, "New combat cancels an unfinished ending")
	music.update_aggression(0, 3.1)
	music._fade.custom_step(3.0)
	music.update_aggression(4, .25)
	_check(music.state == &"combat" and not music._sting.playing, "New combat also interrupts the boom")
	paused = true
	_check(music._silent or music._players[music._current].stream_paused, "Gameplay track suspends during menu pause")
	var volume := music._players[music._current].volume_linear
	await create_timer(.15, true).timeout
	_check(is_equal_approx(volume, music._players[music._current].volume_linear), "Mission fades suspend during pause")
	paused = false
	if music._silent:
		music.update_aggression(0, 3.1)
		music._fade.custom_step(2.1)
		music._boom_timer.start(.02)
		await create_timer(.05).timeout
		_check(music.state == &"calm", "Silent headless boom still finishes on its owned clock")
	scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(.1).timeout # Let a native audio mixer release stopped streams.


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
