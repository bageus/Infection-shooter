extends SceneTree
const EFFECTS := preload("res://game/bootstrap/app/occlusion_effects.gd")
const SUBJECT := preload("res://game/bootstrap/app/occlusion_subject.gd")
const ZONE := preload("res://game/presentation/office_floor/public/props/darkness_zone.tscn")
var scene: Node3D
var camera: Camera3D
var hero: Node3D
var wall: Node3D
var effects: Node
var prop: MeshInstance3D
var fixture: MeshInstance3D
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _mesh(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = position
	return mesh

func _make_fixture() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	env_node.environment = env
	scene.add_child(env_node)
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 5, 8)
	camera.look_at(Vector3(0, 1, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if "--orthographic" in OS.get_cmdline_user_args() else Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 50.0
	camera.size = 8.0
	camera.far = 100.0
	camera.current = true
	hero = Node3D.new()
	scene.add_child(hero)
	var hero_mesh := _mesh(hero, Vector3(0, 0.8, 0), Vector3(0.7, 1.6, 0.5), Color(0.15, 0.9, 0.1))
	(hero_mesh.material_override as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(hero, Vector3(0.1, 1.1, 0.45), Vector3(0.25, 0.25, 0.1), Color(1, 0.8, 0.1))
	prop = _mesh(scene, Vector3(0.95, 0.8, 0), Vector3(0.5, 0.7, 0.5), Color(0.9, 0.05, 0.05))
	fixture = _mesh(scene, Vector3(-0.8, 2.25, 0), Vector3(0.5, 0.25, 0.5), Color(0.9, 0.05, 0.05))
	wall = Node3D.new()
	wall.add_to_group("camera_occluder")
	scene.add_child(wall)
	wall.position = Vector3(0, 1, 3)
	_mesh(wall, Vector3.ZERO, Vector3(7, 6, 0.3), Color(0.32, 0.32, 0.32))
	var body := StaticBody3D.new()
	wall.add_child(body)
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(7, 6, 0.3)
	shape.shape = bounds
	body.add_child(shape)
	effects = EFFECTS.new()
	scene.add_child(effects)
	effects.setup(hero, camera, scene)
	effects.set_mode(1)

func _settle() -> void:
	for frame in 12:
		await physics_frame
		await process_frame

func _run() -> void:
	root.size = Vector2i(640, 480)
	root.msaa_3d = Viewport.MSAA_DISABLED
	_make_fixture()
	_test_morph_copy()
	await _settle()
	_check(effects.subjects.size() == 1 and effects.subjects[0].textured, "X-ray only copies the hero with authored materials")
	_check(effects.get("_hero_blocked") and effects.subjects[0].copies[0].visible, "Blocked hero has an active reveal pass")
	_check(not prop.has_meta("occlusion_copy") and prop.get_child_count() == 0 and fixture.get_child_count() == 0, "Furniture and ceiling fixtures have no reveal copies")
	await _pixels("wall")
	wall.position.x = 20
	await _settle()
	_check(not effects.subjects[0].copies[0].visible, "Visible hero keeps the original pass only")
	await _pixels("clear")
	var fog := ZONE.instantiate() as Node3D
	fog.position = Vector3(0, 1.8, 0)
	scene.add_child(fog)
	fog.call("configure_zone", Vector2(30, 60), 1.0, true)
	await _settle()
	_check(effects.get("_hero_fog_blocked"), "Room cover blocks the hero without a wall")
	_check(effects.subjects[0].copies[0].get_active_material(0).get_shader_parameter("force_visible") == true, "Hero-only pass also works over depth-less fog")
	# Both controls remain compatible, but lens parameters cannot reveal the room.
	fog.call("set_view_hole", Vector2(0.5, 0.5), Vector2(640, 480), 250.0, 20.0)
	await _pixels("fog")
	effects.set_runtime_enabled(false)
	_check(effects.subjects.is_empty(), "Planner/teardown releases the hero pass")
	scene.free()
	await process_frame
	print("Hero x-ray tests: %d failure(s)." % failures)
	quit(failures)

func _test_morph_copy() -> void:
	var target := Node3D.new()
	scene.add_child(target)
	target.position.x = 30.0
	var source := MeshInstance3D.new()
	var array_mesh := ArrayMesh.new()
	array_mesh.add_blend_shape("GripCorrection")
	var arrays := BoxMesh.new().surface_get_arrays(0)
	var shape: Array = []
	shape.resize(Mesh.ARRAY_MAX)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT]:
		shape[slot] = arrays[slot].duplicate()
	var shapes: Array[Array] = [shape]
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	source.mesh = array_mesh
	target.add_child(source)
	source.set_blend_shape_value(0, 0.65)
	var subject := SUBJECT.new(target, Color.CYAN, true)
	subject.set_revealed(true)
	_check(is_equal_approx(subject.copies[0].get_blend_shape_value(0), 0.65), "Hero pass preserves grip/morph corrections")
	source.set_blend_shape_value(0, 0.25)
	subject.set_revealed(true)
	_check(is_equal_approx(subject.copies[0].get_blend_shape_value(0), 0.25), "Live morph changes reach the hero pass")
	subject.clear()
	target.queue_free()


func _pixel(image: Image, point: Vector3) -> Color:
	var pos := camera.unproject_position(point) * Vector2(image.get_size()) / root.get_visible_rect().size
	return image.get_pixel(clampi(roundi(pos.x), 0, image.get_width() - 1), clampi(roundi(pos.y), 0, image.get_height() - 1))

func _pixels(stage: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var hero_pixel := _pixel(image, Vector3(0, 0.8, 0.26))
	_check(hero_pixel.g > hero_pixel.r + 0.15, stage + ": hero retains authored green colour")
	var plate := _pixel(image, Vector3(0.1, 1.1, 0.5))
	_check(plate.r > plate.b + 0.2 and plate.r > plate.g * 0.9, stage + ": front gear preserves self-occlusion and colour")
	for mesh in [prop, fixture]:
		var pixel := _pixel(image, mesh.global_position)
		if stage == "clear":
			_check(pixel.r > pixel.g + 0.15, "Clear view keeps normal props visible")
		else:
			_check(pixel.r < pixel.g + 0.1, stage + ": occluded furniture/fixture stays hidden")
	var directory := OS.get_environment("XRAY_CAPTURE_DIR")
	if not directory.is_empty(): image.save_png(directory.path_join("hero_xray_" + RenderingServer.get_current_rendering_method() + "_" + stage + ".png"))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
