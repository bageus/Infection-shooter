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
	await _bars_follow_the_setting()
	print("Enemy health bar tests: %d failures" % failures)
	quit(1 if failures else 0)


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
	bars.call("set_enabled", false)
	_check(not bars.visible and not bars.is_processing(), "Turning the setting off hides the bars and stops drawing")
	stage.queue_free()
	await process_frame
