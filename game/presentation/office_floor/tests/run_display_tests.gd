extends SceneTree

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const WALL := preload("res://game/presentation/office_floor/public/display_wall.gd")
const PROFILES := preload("res://game/presentation/office_floor/display_surface_profiles.gd")
const CONTENT := preload("res://game/presentation/office_floor/display_content.gd")
const MODEL_ROOT := "res://models/objects/enviroments/05/"
var failures := 0
var stage: Node3D
var wall: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	wall = WALL.new()
	stage.add_child(wall)
	_test_timing()
	for model: String in PROFILES.MODELS:
		_test_model(model)
	await _test_wall()
	if DisplayServer.get_name() != "headless":
		await _test_pixels()
	stage.queue_free()
	await process_frame
	await process_frame
	print("Display tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _spawn(model: String, seed: int = 2, mode: String = "static") -> Node3D:
	var prop := PROP.instantiate() as Node3D
	prop.set("model_path", MODEL_ROOT + model)
	prop.call("configure_display", {"power": "on", "content": mode, "seed": seed})
	prop.call("configure_displays", wall)
	stage.add_child(prop)
	prop.set("freeze", true)
	return prop


func _test_timing() -> void:
	var content := CONTENT.new()
	for i in range(3):
		var timing: Dictionary = content.timeline(i)
		_check((timing["ends"] as Array).size() == [94, 112, 92][i], "Every authored GIF frame has a timing slot")
		_check(is_equal_approx(float(timing["total"]), [5.0, 10.0, 4.6][i]), "Original GIF duration survives baking")
		_check(content.frame_rect(i, 0) == content.frame_rect(i, float(timing["total"])), "Animation loops exactly")
		_check(content.frame_rect(i, float(timing["ends"][0]) - .001) == content.frame_rect(i, 0), "First 50 ms frame is held")
		_check(content.frame_rect(i, float(timing["ends"][0]) + .001) != content.frame_rect(i, 0), "Animation advances at the authored boundary")
	for index in range(16):
		var material := content.material(false, index)
		var rectangle: Vector4 = material.get_shader_parameter("atlas_rect")
		_check(rectangle.x >= 0 and rectangle.y >= 0 and rectangle.x + rectangle.z <= 1 and rectangle.y + rectangle.w <= 1,
			"Static atlas cell stays inside texture")


func _test_model(model: String) -> void:
	var prop := _spawn(model)
	_check(prop.call("has_display"), "Display detected: " + model)
	var view: Node3D = prop.get("_display")
	var screens: Array = view.get("screens")
	_check(screens.size() == (2 if "_server_" in model else 1), "Correct physical screen count: " + model)
	for screen: Dictionary in screens:
		var mesh := screen["mesh"] as MeshInstance3D
		var light := screen["light"] as SpotLight3D
		_check(mesh.mesh.get_surface_count() == 1, "Screen overlay contains only extracted face geometry")
		_check(light.visible and light.spot_angle < 90, "Powered glow stays in the forward hemisphere")
		var front: Vector3 = PROFILES.vector(screen["profile"]["normal"])
		_check((-light.basis.z).dot(front) > .999, "Glow axis follows the authored display front")
		_check((mesh.material_override as ShaderMaterial).get_shader_parameter("powered"), "On screen is powered")
	if screens.size() == 2:
		_check(screens[0]["index"] != screens[1]["index"], "Double monitors have distinct static images")
	prop.call("configure_display", {"power": "on", "content": "dynamic", "seed": 2})
	if screens.size() == 2:
		_check(screens[0]["index"] != screens[1]["index"], "Double monitors have distinct animations")
	if "wall_TV" in model:
		prop.call("configure_display", {"power": "on", "content": "static", "seed": 2})
		_check(prop.call("get_display_config")["content"] == "dynamic", "TV always forces dynamic content")
		_check((view.call("wall_frame") as Transform3D).basis.z.normalized().dot(Vector3.BACK) > .999, "TV faces +Z after wall normalization")
	prop.call("configure_display", {"power": "off", "seed": 2})
	_check(not view.get("powered") and not screens[0]["light"].visible, "Off disables both image and glow")
	prop.call("configure_display", {"power": "auto", "seed": 2})
	_check(view.get("powered"), "Auto has reproducible on state")
	prop.call("configure_display", {"power": "auto", "seed": 3})
	_check(not view.get("powered"), "Auto also chooses off")
	prop.call("configure_display", {"power": "on", "content": "dynamic", "seed": 5})
	var config: Dictionary = prop.call("get_display_config")
	var packed := PackedScene.new()
	_check(packed.pack(prop) == OK, "Authored display packs")
	var copy := packed.instantiate()
	_check(copy.call("get_display_config") == config, "Exported display config survives scene packing")
	copy.free()
	prop.call("take_projectile_hit", 1.0, prop.global_position, Vector3.FORWARD, Vector3.FORWARD, "pistol")
	_check(not view.get("powered"), "First electrical damage switches screen off")
	_check(prop.call("get_display_config") == config, "Damage does not overwrite authored display state")
	prop.queue_free()


func _test_wall() -> void:
	await process_frame
	_check((wall.get("displays") as Array).is_empty(), "Freed displays unregister without stale references")
	var model := "05_wall_TV_frameless_destructible.glb"
	var a := _spawn(model, 2)
	var b := _spawn(model, 5)
	var c := _spawn(model, 7)
	b.position.x = 1.0486208
	c.position = Vector3(1.0486208, .55763054, 0)
	await create_timer(.18).timeout
	var av: Node3D = a.get("_display")
	var bv: Node3D = b.get("_display")
	var cv: Node3D = c.get("_display")
	var ar := _rect(av)
	var br := _rect(bv)
	_check(is_equal_approx(ar.z, .5) and is_equal_approx(ar.w, .5), "Connected 2D wall stretches one image over its total bounds")
	_check(is_equal_approx(ar.x + ar.z, br.x), "Adjacent horizontal UV edges meet")
	_check(av.get("screens")[0]["index"] == cv.get("screens")[0]["index"], "Whole wall shares one screensaver")
	b.call("configure_display", {"power": "off", "seed": 5})
	await create_timer(.18).timeout
	_check(not bv.get("powered") and _rect(bv).z == .5, "Off panel remains dark inside the shared wall")
	c.position.z = .1
	await create_timer(.18).timeout
	_check(_rect(cv) == Vector4(0, 0, 1, 1), "Parallel panels on different planes remain separate")
	c.position = Vector3(1.0486208, 0, 0)
	c.rotation.y = PI
	await create_timer(.18).timeout
	_check(_rect(cv) == Vector4(0, 0, 1, 1), "Back-facing panels do not merge")
	b.queue_free()
	await create_timer(.18).timeout
	_check(_rect(av) == Vector4(0, 0, 1, 1), "Deleting a neighbor splits and restores a full local image")
	a.queue_free()
	c.queue_free()
	await process_frame


func _rect(view: Node3D) -> Vector4:
	return (view.get("screens")[0]["mesh"].material_override as ShaderMaterial).get_shader_parameter("content_rect")


func _test_pixels() -> void:
	# Render one extracted face in a black room.
	# Shader compilation and real GPU texture loads happen only in this path.
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLACK
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(2.0, 1.0, 2.8)
	camera.look_at_from_position(camera.position, Vector3(0, .4, 0))
	camera.current = true
	stage.add_child(camera)
	var prop := _spawn("05_monitor2_destructible.glb", 4)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty(), "GPU produces a display frame")
	var lit_pixels := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.b > .08 and pixel.b > pixel.r * 1.2:
				lit_pixels += 1
	_check(lit_pixels > 100, "Screen texture visibly covers the display face")
	var capture := OS.get_environment("DISPLAY_CAPTURE_DIR")
	if not capture.is_empty():
		DirAccess.make_dir_recursive_absolute(capture)
		image.save_png(capture.path_join("display_%s.png" % RenderingServer.get_current_rendering_method()))
	prop.queue_free()
	camera.queue_free()
	world.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
