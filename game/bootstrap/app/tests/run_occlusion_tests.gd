extends SceneTree

const EFFECTS := preload("res://game/bootstrap/app/occlusion_effects.gd")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
const MAIN := preload("res://game/bootstrap/app/main.tscn")
var failures := 0
var scene: Node3D
var camera: Camera3D
var hero: Node3D
var wall: Node3D
var effects: Node
var original: StandardMaterial3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_make_fixture()
	await _settle()
	_check(effects.call("_blocked", hero), "wall occludes hero")
	wall.remove_from_group("camera_occluder")
	_check(not effects.call("_blocked", hero), "unclassified furniture never triggers reveal")
	wall.add_to_group("camera_occluder")
	_check(effects.subjects.size() == 3, "hero, enemy and item classified")
	for subject in effects.subjects:
		_check(not subject.copies.is_empty() and subject.copies[0].visible, "blocked subject has visual copy")
	await _render_checks()
	wall.position.x = 20.0
	await _settle()
	_check(not effects.call("_blocked", hero), "unobstructed hero")
	for subject in effects.subjects:
		_check(not subject.copies[0].visible, "visible subjects are not highlighted")
	wall.position.x = 0.0
	var rebuilds: int = effects.rebuild_count
	var hero_copy: MeshInstance3D = effects.subjects[0].copies[0]
	var added := _actor(Vector3(1, 0, 0), "infected")
	await _settle()
	_check(effects.subjects.size() == 4, "late spawned enemy is registered")
	_check(effects.rebuild_count == rebuilds and is_instance_valid(hero_copy), "Spawning an enemy preserves existing silhouettes without rebuilding the world")
	added.queue_free()
	await _settle()
	_check(effects.subjects.size() == 3, "removed enemy is released")
	_check(effects.rebuild_count == rebuilds and is_instance_valid(hero_copy), "Removing an enemy preserves existing silhouettes")
	var outsider := Node3D.new()
	outsider.add_to_group("infected")
	root.add_child(outsider)
	await _settle()
	_check(effects.subjects.size() == 3, "Objects outside the injected world are ignored")
	outsider.queue_free()
	for cycle in 5:
		effects.set_mode(1)
		await _settle()
		_check(effects.walls.records.size() == 1 and effects.subjects.is_empty(), "hole mode only overrides structural wall")
		_check(effects.get("_hero_blocked"), "hole is gated by hero blocker")
		var wall_rebuilds: int = effects.rebuild_count
		scene.remove_child(wall)
		await _settle()
		_check(_wall_mesh().material_override == original and effects.walls.records.is_empty(), "Detached wall restores authored materials")
		scene.add_child(wall)
		await _settle()
		_check(effects.walls.records.size() == 1 and effects.rebuild_count == wall_rebuilds, "Reattached wall is installed without rebuilding other roots")
		effects.set_runtime_enabled(false)
		_check(_wall_mesh().material_override == original, "planner restores material_override")
		_check(_wall_mesh().get_surface_override_material(0) == null, "planner restores original surface override exactly")
		effects.set_runtime_enabled(true)
		await _settle()
		effects.set_mode(0)
		_check(_wall_mesh().material_override == original, "silhouette mode restores wall material")
	scene.free()
	await process_frame
	await _integration()
	print("Occlusion tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _make_fixture() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	environment.environment = env
	scene.add_child(environment)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 2, 8)
	camera.look_at(Vector3(0, 1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.current = true
	hero = _actor(Vector3.ZERO, "player")
	_actor(Vector3(-2, 0, 0), "infected")
	_actor(Vector3(2, 0, 0), "occlusion_items")
	wall = Node3D.new()
	wall.add_to_group("camera_occluder")
	scene.add_child(wall)
	wall.position = Vector3(0, 1, 3)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(7, 4, 0.3)
	mesh.mesh = box
	original = StandardMaterial3D.new()
	original.albedo_color = Color(0.32, 0.32, 0.32)
	mesh.material_override = original
	wall.add_child(mesh)
	var body := StaticBody3D.new()
	wall.add_child(body)
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = box.size
	shape.shape = bounds
	body.add_child(shape)
	effects = EFFECTS.new()
	effects.name = "OcclusionEffects"
	scene.add_child(effects)
	effects.setup(hero, camera, scene)


func _actor(position: Vector3, group: String) -> Node3D:
	var actor := Node3D.new()
	actor.add_to_group(group)
	scene.add_child(actor)
	actor.position = position
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(0.7, 1.6, 0.5)
	mesh.position.y = 0.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 0.2)
	mesh.material_override = material
	actor.add_child(mesh)
	return actor


func _wall_mesh() -> MeshInstance3D:
	return wall.get_child(0) as MeshInstance3D


func _settle() -> void:
	for frame in 10:
		await physics_frame
		await process_frame


func _render_checks() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var colored := root.get_texture().get_image()
	var center := camera.unproject_position(Vector3(0, 0.8, 0))
	_capture(colored, "silhouettes")
	var pixel := colored.get_pixelv(Vector2i(center))
	_check(pixel.b > pixel.r + 0.2, "hidden hero pixels are cyan")
	var enemy := colored.get_pixelv(Vector2i(camera.unproject_position(Vector3(-2, 0.8, 0))))
	_check(enemy.r > enemy.g + 0.2, "hidden enemy pixels are red")
	var item := colored.get_pixelv(Vector2i(camera.unproject_position(Vector3(2, 0.8, 0))))
	_check(item.r > item.b + 0.2 and item.g > item.b + 0.2, "hidden item pixels are amber")
	effects.set_mode(1)
	await _settle()
	await RenderingServer.frame_post_draw
	var hole := root.get_texture().get_image()
	_capture(hole, "hole")
	var exposed := hole.get_pixelv(Vector2i(center))
	_check(exposed.g > exposed.r + 0.15, "hole reveals authored green hero")
	var outside := hole.get_pixelv(Vector2i(camera.unproject_position(Vector3(-3, 0.8, 3))))
	_check(absf(outside.r - outside.g) < 0.05, "wall outside radius remains opaque")
	wall.position.x = 20.0
	effects.set_mode(0)
	await _settle()
	await RenderingServer.frame_post_draw
	effects.set_physics_process(false)
	for subject in effects.subjects:
		subject.set_revealed(true)
	await process_frame
	await RenderingServer.frame_post_draw
	var visible := root.get_texture().get_image().get_pixelv(Vector2i(center))
	_check(visible.g > visible.b + 0.15, "visible hero retains authored color")
	effects.set_physics_process(true)
	wall.position.x = 0.0
	await _settle()


func _integration() -> void:
	var had := FileAccess.file_exists(PREFS.FILE)
	var saved := FileAccess.get_file_as_bytes(PREFS.FILE) if had else PackedByteArray()
	var prefs := PREFS.new()
	prefs.values.occlusion_mode = 1
	_check(prefs.save_settings() == OK, "preference saved")
	var loaded := PREFS.new()
	loaded.load_settings()
	_check(loaded.values.occlusion_mode == 1, "preference reloaded")
	var app := MAIN.instantiate()
	root.add_child(app)
	current_scene = app
	await process_frame
	var runtime := app.get_node("OcclusionEffects")
	loaded.apply_to_game(self)
	await _settle()
	_check(runtime.mode == 1, "setting reaches game immediately")
	var planner: Node = app.get("planning_mode")
	for cycle in 3:
		planner.call("enter")
		_check(not runtime.runtime_enabled and runtime.mode == 1, "planner suspends but keeps selection")
		planner.call("exit")
		_check(runtime.runtime_enabled and runtime.mode == 1, "planner restores selection")
	# Exercise real authored map material allocation and teardown repeatedly.
	for cycle in 12:
		runtime.set_mode(cycle % 2)
		for frame in 20:
			await process_frame
		_check(runtime.walls.pending.size() < 10000, "bounded material installation queue")
	loaded.values.occlusion_mode = 0
	loaded.apply_to_game(self)
	_check(runtime.mode == 0, "runtime switch back")
	await _settle()
	for subject in runtime.subjects:
		if subject.target.get_ref() == app.get("player"):
			subject.set_revealed(true)
			_check(not subject.copies.is_empty(), "real player mesh has silhouette")
			for copy: MeshInstance3D in subject.copies:
				var source := copy.get_parent() as MeshInstance3D
				_check(copy.mesh == source.mesh and copy.skin == source.skin, "copy shares live mesh and skin")
				var skeleton := source.get_node_or_null(source.skeleton)
				if skeleton is Skeleton3D:
					_check(copy.get_node(copy.skeleton) == skeleton, "copy follows the real skeleton")
	app.free()
	paused = false
	await process_frame
	if had:
		var file := FileAccess.open(PREFS.FILE, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else:
		DirAccess.remove_absolute(PREFS.FILE)


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _capture(image: Image, label: String) -> void:
	var directory := OS.get_environment("OCCLUSION_CAPTURE_DIR")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	image.save_png(directory.path_join("occlusion_" + RenderingServer.get_current_rendering_method() + "_" + label + ".png"))
