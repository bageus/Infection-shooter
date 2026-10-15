extends SceneTree
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const SHADOWS := preload("res://game/presentation/office_floor/prop_shadow_policy.gd")
const MODELS := "res://models/objects/enviroments/"
var stage: Node3D
var samples: Array[int] = []
var output := "/tmp/prop-shadow-before"
var camera: Camera3D
var baseline := false

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	for arg in OS.get_cmdline_user_args():
		if arg == "--baseline":
			baseline = true
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	seed(981)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.11, .14, .19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.8, .86, 1)
	environment.ambient_light_energy = .55
	world.environment = environment
	stage.add_child(world)
	var floor_visual := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(12, .2, 9)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.48, .51, .55)
	floor_mesh.material = material
	floor_visual.mesh = floor_mesh
	floor_visual.position.y = -.1
	stage.add_child(floor_visual)
	var key := DirectionalLight3D.new()
	key.light_energy = .7
	key.rotation_degrees = Vector3(-55, -25, 0)
	stage.add_child(key)
	var spot := SpotLight3D.new()
	spot.position = Vector3(-1.5, 5, 2.5)
	spot.spot_range = 15
	spot.spot_angle = 60
	spot.light_energy = 8
	spot.shadow_enabled = true
	stage.add_child(spot)
	spot.look_at(Vector3.ZERO)
	var table := _prop("07/07_table_longest.glb", Vector3(-.7, 0, 0))
	var table_top := _bounds(table).end.y
	_prop("06/06_simple_chair.glb", Vector3(-1.8, 0, 1.1))
	var small := ["09/09_book_small.glb", "09/09_book_big.glb", "09/09_mug.glb", "09/09_plastic_water_bottle_blue_500ml.glb", "09/09_glass_water_bottle_green_330ml.glb"]
	for index in small.size():
		_prop(small[index], Vector3(-1.7 + index * .45, table_top + .005, -.15))
	for index in 10:
		_prop(small[index % small.size()], Vector3(1.2 + (index % 5) * .4, .005, -.6 + (index / 5) * .7))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.5
	camera.position = Vector3(6, 7, 9)
	stage.add_child(camera)
	camera.look_at(Vector3(0, .6, 0))
	camera.current = true
	# Stable visual comparison: no gravity, damage or body settling during either capture.
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	for frame in 30:
		await process_frame
	var previous := Time.get_ticks_usec()
	for frame in 239:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(now - previous)
		previous = now
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	_save(output.path_join("overview.png"))
	camera.size = 3.0
	camera.position = Vector3(3, 4, 5)
	camera.look_at(Vector3(-.7, table_top, 0))
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	_save(output.path_join("detail.png"))
	var total := 0
	for usec in samples:
		total += usec
	samples.sort()
	print(JSON.stringify({"baseline": baseline, "render_frames": samples.size(), "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "wall_mean_ms": float(total) / samples.size() / 1000.0,
		"wall_p95_ms": samples[int(samples.size() * .95)] / 1000.0, "output": output}))
	stage.free()
	await process_frame
	quit()

func _prop(model: String, point: Vector3) -> RigidBody3D:
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", MODELS + model)
	stage.add_child(prop)
	prop.freeze = true
	if baseline:
		SHADOWS.restore(prop.get_node("Visual"))
	var bounds := _bounds(prop)
	# Model pivots differ: point is the requested footprint centre and bottom height.
	prop.global_position += Vector3(point.x - bounds.get_center().x, point.y - bounds.position.y, point.z - bounds.get_center().z)
	prop.force_update_transform()
	print(model, " bounds=", _bounds(prop).size)
	return prop

func _bounds(prop: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for child in prop.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh != null and mesh.is_visible_in_tree():
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			result = bounds if not found else result.merge(bounds)
			found = true
	return result


func _save(path: String) -> void:
	var screenshot := root.get_texture().get_image()
	if screenshot.is_empty() or screenshot.save_png(path) != OK:
		push_error("Rendered comparison could not be saved: " + path)
		quit(1)
