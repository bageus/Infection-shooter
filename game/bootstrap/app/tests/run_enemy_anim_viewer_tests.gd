extends SceneTree
## Enemy animation page: finds every enemy scene, merges the clips the game plays on each body, and builds its UI.
const CATALOG := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_catalog.gd")
const VIEWER := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_viewer.tscn")
const TIMELINE := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_timeline.gd")
const VIEWER_SCRIPT := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_viewer.gd")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths := CATALOG.enemy_scene_paths()
	_expect(paths.has("res://game/features/infected/public/infected_brute.tscn"), "Brute scene is found")
	_expect(paths.has("res://game/features/infected/public/infected_titan.tscn"), "Titan scene is found")
	var sorted := paths.duplicate()
	sorted.sort()
	_expect(paths == sorted, "Enemy list is sorted by file name")
	_expect(CATALOG.enemy_name("res://x/infected_brute.tscn") == "Brute", "Display name drops the prefix")

	var brute := CATALOG.load_body("res://game/features/infected/public/infected_brute.tscn")
	_expect(brute != null, "Brute loads an animated body")
	if brute != null:
		var player := CATALOG.find_player(brute)
		_expect(player != null and player.has_animation("Idle"), "Brute body has its Idle clip")
		var extra := load("res://models/objects/characters/enemy/game/Brute_mixamo.res") as AnimationLibrary
		var missing := 0
		for clip in extra.get_animation_list():
			if player == null or not player.has_animation(clip):
				missing += 1
		_expect(missing == 0, "Brute body has every extra clip the game merges (%d missing)" % missing)
		brute.free()

	var horde := CATALOG.load_body("res://game/features/infected/public/infected_horde.tscn")
	_expect(horde != null and CATALOG.find_player(horde).has_animation("Idle"), "Horde loads with Idle")
	if horde != null:
		horde.free()

	var hunger := CATALOG.load_body("res://game/features/infected/public/infected_hunger.tscn")
	var levels: Array[int] = VIEWER_SCRIPT._lod_levels(hunger)
	_expect(levels.size() == 3 and levels[0] > levels[1] and levels[1] > levels[2], "Hunger has LOD0-2 with fewer triangles each: %s" % [levels])
	_expect(VIEWER_SCRIPT.current_lod(levels, levels[1] + 10) == 1, "Drawn triangles near LOD1 read as LOD1")
	hunger.free()

	_test_timeline()
	var viewer := VIEWER.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame
	_expect(viewer.get_child_count() == 1, "Viewer builds one page root")
	viewer.free()
	print("Enemy animation viewer tests: %d failure(s)." % failures)
	quit(failures)


func _test_timeline() -> void:
	var titan := CATALOG.load_body("res://game/features/infected/public/infected_titan.tscn")
	var player := CATALOG.find_player(titan)
	root.add_child(titan)
	for preset: String in TIMELINE.PRESETS:
		var clips := TIMELINE.preset_clips(preset, player.get_animation_list())
		_expect(clips.size() == (TIMELINE.PRESETS[preset] as Array).size(), "Titan has every clip of the preset %s (%s)" % [preset, clips])
	var chain := TIMELINE.new()
	chain.entries.assign(TIMELINE.preset_clips("Ходьба → переход → Idle", player.get_animation_list()))
	chain.start(player)
	_expect(chain.playing and chain.current == 0 and player.current_animation == "Walk", "A chain starts with its first clip")
	chain.step(TIMELINE.HOLD + 0.01, player, true, false)
	_expect(chain.current == 0, "A paused chain does not advance")
	chain.step(TIMELINE.HOLD + 0.01, player, false, false)
	_expect(chain.current == 1 and player.current_animation == "Transition", "A looping clip holds, then the next clip plays")
	chain.step(player.get_animation("Transition").length + 0.01, player, false, false)
	_expect(chain.current == 2 and chain.playing, "The transition leads on to the idle")
	chain.step(player.get_animation("Idle").length + 0.01, player, false, false)
	_expect(not chain.playing, "A chain stops after its last clip when not repeating")
	chain.entries.assign(["Idle", "DeathBack"])
	chain.start(player)
	chain.step(player.get_animation("Idle").length + 0.01, player, false, false)
	_expect(player.get_animation("DeathBack").loop_mode == Animation.LOOP_NONE and player.current_animation == "DeathBack", "A death plays once")
	# An attack whose strike lands after the wind-up (Titan's AttackLeft strikes at 0.3 s, like Brute's and Colossus').
	var attack_name := "AttackLeft"
	for clip in player.get_animation_list():
		if clip.begins_with("Attack") and float(player.get_animation(clip).get_meta("strike_time", 0.0)) > TIMELINE.STRIKE_WINDUP:
			attack_name = clip
			break
	var attack := player.get_animation(attack_name)
	_expect(TIMELINE.speed_of(attack) > 1.0 and absf(TIMELINE.seconds_of(attack_name, attack) - attack.length / TIMELINE.speed_of(attack)) < 0.001, "Attacks play at the game's speed")
	titan.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
