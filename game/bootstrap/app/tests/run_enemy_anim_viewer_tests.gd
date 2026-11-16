extends SceneTree
## Enemy animation page: finds every enemy scene, merges the clips the game plays on each body, and builds its UI.
const CATALOG := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_catalog.gd")
const VIEWER := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_viewer.tscn")
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

	var viewer := VIEWER.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame
	_expect(viewer.get_child_count() == 1, "Viewer builds one page root")
	viewer.free()
	print("Enemy animation viewer tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
