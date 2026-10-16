extends SceneTree
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const BULLET := preload("res://game/features/combat/public/prototype_bullet.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	await _projection_and_budget()
	await _preferences()
	await create_timer(0.2).timeout
	print("Bullet smoke tests: %d failures" % failures)
	quit(1 if failures else 0)

func _projection_and_budget() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var impacts := IMPACTS.new()
	stage.add_child(impacts)
	var wall := StaticBody3D.new()
	var visual := MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	wall.add_child(visual)
	stage.add_child(wall)
	impacts.register_surface(wall, visual)
	var bullet := BULLET.instantiate()
	stage.add_child(bullet)
	bullet.set_physics_process(false)
	bullet.configure_world(stage, impacts)
	bullet.set("_direction", Vector3.FORWARD)
	bullet._spawn_impact_decal(wall, Vector3(0, 0, 0.5), Vector3.BACK)
	var smoke: Node = impacts.get("_bullet_smoke")
	_check(smoke != null and smoke.get_child_count() == 1, "Confirmed mark projection spawns one dust puff")
	_check(not impacts.get("_marks").is_empty(), "Dust preserves the actual bullet mark")
	var puff := smoke.get_child(0) as GPUParticles3D if smoke != null else null
	_check(puff != null and puff.amount == 3 and puff.lifetime < 0.5 and puff.position.z > 0.5, "Small short puff is offset outside the receiver")
	for i in 100:
		impacts.spawn_bullet_smoke(Vector3.ZERO, Vector3.UP)
	_check(smoke.get_child_count() <= 2, "Shotgun/minigun flood admits only two puffs per physics frame")
	for i in 12:
		await physics_frame
		impacts.spawn_bullet_smoke(Vector3.ZERO, Vector3.UP)
		impacts.spawn_bullet_smoke(Vector3.ZERO, Vector3.UP)
	_check(smoke.get_child_count() <= 16, "Concurrent emitter cap holds across frames")
	impacts.bullet_smoke_enabled = false
	await process_frame
	_check(smoke.get_child_count() == 0 and not impacts.get("_marks").is_empty(), "Disabling clears only live smoke, keeping bullet marks")
	bullet._spawn_impact_decal(wall, Vector3(0, 0, 0.5), Vector3.BACK)
	_check(smoke.get_child_count() == 0, "Disabled setting blocks new smoke on real marks")
	impacts.bullet_smoke_enabled = true
	await physics_frame
	var invisible := StaticBody3D.new()
	stage.add_child(invisible)
	bullet._spawn_impact_decal(invisible, Vector3.ZERO, Vector3.UP)
	_check(smoke.get_child_count() == 0, "No visible receiving geometry means no decal smoke")
	bullet._spawn_impact_decal(wall, Vector3(0, 0, 0.5), Vector3.BACK)
	_check(smoke.get_child_count() == 1, "Re-enabling allows the next confirmed hit")
	await create_timer(0.65).timeout
	_check(smoke.get_child_count() == 0, "Expired emitters are freed even with a headless renderer")
	stage.queue_free()
	await process_frame

func _preferences() -> void:
	var had := FileAccess.file_exists(PREFS.FILE)
	var saved := FileAccess.get_file_as_bytes(PREFS.FILE) if had else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("interface_v1", "electronic_particles", false)
	_check(config.save(PREFS.FILE) == OK, "Legacy fixture saves")
	var legacy := PREFS.new()
	legacy.load_settings()
	_check(legacy.values.bullet_impact_smoke and not legacy.values.electronic_particles, "Legacy config defaults smoke on without overriding sparks")
	config.set_value("interface_v1", "bullet_impact_smoke", "false")
	config.save(PREFS.FILE)
	var malformed := PREFS.new()
	malformed.load_settings()
	_check(malformed.values.bullet_impact_smoke, "Wrong config type retains the safe typed default")
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var impacts := IMPACTS.new()
	impacts.name = "ImpactEffects"
	stage.add_child(impacts)
	legacy.values.bullet_impact_smoke = false
	legacy.apply_to_game(self)
	_check(not impacts.bullet_smoke_enabled, "Saved preference reaches the real combat pool")
	legacy.save_settings()
	var loaded := PREFS.new()
	loaded.load_settings()
	_check(not loaded.values.bullet_impact_smoke, "Disabled smoke survives save/reload")
	loaded.reset()
	loaded.apply_to_game(self)
	_check(impacts.bullet_smoke_enabled, "Reset restores smoke on the active pool")
	stage.queue_free()
	await process_frame
	if had:
		var file := FileAccess.open(PREFS.FILE, FileAccess.WRITE)
		file.store_buffer(saved)
	else:
		DirAccess.remove_absolute(PREFS.FILE)
