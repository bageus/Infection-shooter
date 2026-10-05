extends SceneTree
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var had := FileAccess.file_exists(PREFS.FILE)
	var saved := FileAccess.get_file_as_bytes(PREFS.FILE) if had else PackedByteArray()
	var prefs := PREFS.new()
	prefs.values.occlusion_mode = 1
	prefs.save_settings()
	var app := MAIN.instantiate()
	root.add_child(app)
	current_scene = app
	await process_frame
	prefs.apply_to_game(self)
	for enemy in app.enemies.get_children():
		enemy.queue_free()
	var hero: Node3D = app.player
	var runtime: Node = app.infection_runtime
	var effects: Node = app.get_node("OcclusionEffects")
	var debug: Node = app.get_node("RuntimeDebug")
	_check(effects.mode == 1, "Saved hole mode applies at launch")
	_check(app.gameplay.get_node_or_null("PermanentTestMutagen") == null, "Normal launch has no infectious test cloud")
	var start: Vector3 = hero.global_position
	for frame in 150:
		# Move through different camera occlusion positions without combat exposure.
		hero.global_position = start + Vector3(sin(frame * .08) * 2.0, 0, cos(frame * .08))
		await physics_frame
		await process_frame
	_check(is_zero_approx(float(runtime.call("get_mutation"))) and not runtime.call("is_control_lost"), "Hole rendering does not infect or remove player control")
	_check(effects.walls.pending.is_empty(), "Wall installation queue drains during movement")
	var variants: Array = effects.walls.active_materials.duplicate()
	var late := Node3D.new()
	late.add_to_group("infected")
	app.add_child(late)
	for frame in 12:
		await physics_frame
		await process_frame
	for material in variants:
		_check(effects.walls.active_materials.has(material), "Late actor registration reuses existing hole materials")
	late.free()
	var mutation_before: float = runtime.call("get_mutation")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_F3
	debug.call("_unhandled_key_input", key)
	_check(debug.label.visible and debug.label.text.contains("Mutation"), "F3 shows runtime diagnostics")
	_check(float(runtime.call("get_mutation")) == mutation_before, "Diagnostics are read-only")
	app.set_test_mutagen_enabled(true)
	var cloud: Node = app.gameplay.get_node("PermanentTestMutagen")
	_check(cloud.is_physics_processing() and cloud.visible, "Test cloud requires explicit opt-in")
	app.set_test_mutagen_enabled(false)
	await physics_frame
	_check(not cloud.is_physics_processing() and not cloud.visible and not cloud.monitoring, "Disabling test cloud stops absorption and hides it")
	runtime.call("absorb_mutagen", 6.2)
	_check(runtime.call("is_control_lost"), "Legitimate mutation control loss is preserved")
	runtime.call("add_control_ampule")
	runtime.call("_physics_process", 5.0)
	_check(not runtime.call("is_control_lost"), "Existing control recovery remains available")
	var bottle: PackedScene = load("res://models/objects/enviroments/02/02_water_cooler_bottle.glb")
	_check(bottle != null, "Water bottle imports with its committed texture")
	if bottle != null:
		for i in 4:
			var instance := bottle.instantiate()
			app.add_child(instance)
			_check(not instance.find_children("*", "MeshInstance3D", true, false).is_empty(), "Each of four bottle placements retains its mesh")
	app.free()
	paused = false
	await process_frame
	if had:
		var file := FileAccess.open(PREFS.FILE, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else:
		DirAccess.remove_absolute(PREFS.FILE)
	print("Runtime debug tests: %d failures" % failures)
	quit(failures)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
