extends SceneTree
const BARS := preload("res://game/bootstrap/app/enemy_health_bars.gd")
const ENEMY := preload("res://game/features/infected/public/infected_capsule.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	_preference_defaults_and_round_trip()
	_width_follows_max_health()
	_only_same_room()
	await _bars_follow_the_setting()
	print("Enemy health bar tests: %d failures" % failures)
	quit(1 if failures else 0)


func _only_same_room() -> void:
	_check(BARS.same_room([], []) and BARS.same_room([3], [3, 4]), "Open area and a shared room show bars")
	_check(not BARS.same_room([3], []) and not BARS.same_room([], [3]) and not BARS.same_room([3], [4]), "Another room or a room against open area hides bars")
	var stage := Node3D.new()
	root.add_child(stage)
	var zone := (load("res://game/presentation/office_floor/public/props/darkness_zone.tscn") as PackedScene).instantiate() as Node3D
	stage.add_child(zone)
	zone.call("configure_zone", Vector2(10, 10), 1.0, false)
	zone.set("room_id", 7)
	var inside: Array = BARS.rooms_at(self, Vector3(1, 0, 1))
	_check(inside == [7] and BARS.rooms_at(self, Vector3(30, 0, 0)).is_empty(), "A point inside a zone belongs to its room, outside belongs to none")
	stage.free()


func _width_follows_max_health() -> void:
	var hunger: float = BARS.bar_width(45.0)
	var brute: float = BARS.bar_width(135.0)
	var titan: float = BARS.bar_width(520.0)
	var horde: float = BARS.bar_width(2700.0)
	_check(hunger < brute and brute < titan and titan < horde, "Bar width grows with max health")
	_check(is_equal_approx(hunger, BARS.BAR_SIZE.x) and is_equal_approx(horde, BARS.MAX_BAR_WIDTH), "Weakest and strongest enemies get the min and max width")


func _preference_defaults_and_round_trip() -> void:
	var had := FileAccess.file_exists(PREFS.FILE)
	var saved := FileAccess.get_file_as_bytes(PREFS.FILE) if had else PackedByteArray()
	var prefs := PREFS.new()
	_check(prefs.values.enemy_health_bars == false, "Enemy health bars are off by default")
	prefs.values.enemy_health_bars = true
	prefs.save_settings()
	var loaded := PREFS.new()
	loaded.load_settings()
	_check(loaded.values.enemy_health_bars == true, "Enemy health bar setting survives save and reload")
	if had:
		FileAccess.open(PREFS.FILE, FileAccess.WRITE).store_buffer(saved)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS.FILE))


func _bars_follow_the_setting() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 2, 6)
	camera.look_at(Vector3(0, 1, 0))
	camera.make_current()
	var enemy := ENEMY.instantiate() as Node3D
	stage.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set("max_health", 100.0)
	enemy.set("health", 40.0)
	var bars := BARS.new()
	stage.add_child(bars)
	bars.call("setup", camera)
	_check(not bars.visible and not bars.is_processing(), "Bars start hidden and idle")
	bars.call("set_enabled", true)
	_check(bars.visible and bars.is_processing(), "Turning the setting on shows and runs the bars")
	await process_frame
	await process_frame
	_check(is_instance_valid(bars), "Bars draw a live damaged enemy without errors")
	var heights := {}
	var widths := {}
	for key in ["infected_hunger", "infected_brute", "infected_colossus", "infected_titan", "infected_horde"]:
		var kind := (load("res://game/features/infected/public/%s.tscn" % key) as PackedScene).instantiate() as Node3D
		stage.add_child(kind)
		heights[key] = BARS._bar_height(kind)
		widths[key] = BARS.bar_width(float(kind.get("max_health")))
		kind.free()
	_check(widths["infected_horde"] > widths["infected_colossus"] and widths["infected_colossus"] > widths["infected_titan"] and widths["infected_titan"] > widths["infected_brute"] and widths["infected_brute"] > widths["infected_hunger"], "Each real enemy type gets a wider bar the more health it has, horde widest")
	_check(heights["infected_colossus"] > heights["infected_hunger"] and heights["infected_colossus"] > heights["infected_titan"], "Bar height follows each enemy type")
	_check(is_equal_approx(heights["infected_hunger"], 0.925 + 0.3), "Hunger bar sits just above its capsule")
	bars.call("set_enabled", false)
	_check(not bars.visible and not bars.is_processing(), "Turning the setting off hides the bars and stops drawing")
	stage.queue_free()
	await process_frame
