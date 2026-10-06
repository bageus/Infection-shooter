extends SceneTree
## A/B sample only: software CI timings are not a target-device FPS claim.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const WALL := preload("res://game/presentation/office_floor/public/display_wall.gd")
const MODEL := "res://models/objects/enviroments/05/05_monitor2_destructible.glb"
var failures := 0
var lights: Array[SpotLight3D] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Display shadow profile: native renderer required, 0 failures")
		quit()
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var stage := Node3D.new()
	root.add_child(stage)
	var wall := WALL.new()
	stage.add_child(wall)
	for index in 24:
		var prop := PROP.instantiate() as Node3D
		prop.set("model_path", MODEL)
		prop.call("configure_displays", wall)
		prop.call("configure_display", {"power": "on", "content": "dynamic", "seed": index})
		stage.add_child(prop)
		prop.set("freeze", true)
		prop.position = Vector3(float(index % 8) * .8 - 2.8, float(index / 8) * .8, 0)
		for screen: Dictionary in prop.get("_display").get("screens"):
			lights.append(screen["light"])
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12, .1, 8)
	floor_mesh.mesh = box
	floor_mesh.position = Vector3(0, -.1, 2)
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(4, 4, 7), Vector3(0, 1, 1))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.02, .02, .02)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.3, .3, .3)
	environment.environment.ambient_light_energy = .2
	stage.add_child(environment)
	if lights.size() != 24:
		failures += 1
		push_error("Profile must contain 24 powered screen lights")
	var samples: Array[Dictionary] = []
	# ABBA order and warmup reduce order/initial shader compilation bias.
	for enabled: bool in [true, false, false, true]:
		samples.append(await _sample(enabled))
	var output := {"renderer": RenderingServer.get_current_rendering_method(), "screens": lights.size(),
		"samples": samples, "note": "CI software-renderer wall frame time; repeat on target Windows/Web before changing defaults"}
	print("Display shadow profile: " + JSON.stringify(output))
	var folder := OS.get_environment("RUNTIME_PROFILE_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file := FileAccess.open(folder.path_join("display_shadows_%s.json" % RenderingServer.get_current_rendering_method()), FileAccess.WRITE)
		if file == null:
			failures += 1
			push_error("Unable to write shadow profile")
		else:
			file.store_string(JSON.stringify(output, "\t"))
	stage.queue_free()
	await process_frame
	await process_frame
	print("Display shadow profile tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _sample(shadows: bool) -> Dictionary:
	for light in lights:
		light.shadow_enabled = shadows
	for frame in 16:
		await process_frame
		await RenderingServer.frame_post_draw
	var times: Array[float] = []
	for frame in 48:
		var started := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		times.append(float(Time.get_ticks_usec() - started) / 1000.0)
	times.sort()
	return {"shadows": shadows, "median_frame_ms": times[24], "p95_frame_ms": times[45],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0}
