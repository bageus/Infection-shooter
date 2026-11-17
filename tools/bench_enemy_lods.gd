extends SceneTree
## Frame time and drawn triangles of an animated enemy crowd seen by the game camera, LOD on vs off.
##   xvfb-run -a godot --path . --audio-driver Dummy [--rendering-method gl_compatibility] --script tools/bench_enemy_lods.gd -- [count] [camera distance]
const GAME_DIR := "res://models/objects/characters/enemy/game/"
const NAMES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus", "Horde"]
const FRAMES := 20


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var count := int(args[0]) if args.size() > 0 else 40
	var distance := float(args[1]) if args.size() > 1 else 16.0
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 50.0
	stage.add_child(camera)
	camera.position = Vector3(0, sin(deg_to_rad(50.0)), cos(deg_to_rad(50.0))) * distance
	camera.look_at(Vector3.ZERO)
	camera.current = true
	for i in count:
		var rig := (load(GAME_DIR + NAMES[i % NAMES.size()] + "_rig.tscn") as PackedScene).instantiate() as Node3D
		# Spread over the visible floor: a 14 x 8 m patch around the camera target.
		rig.position = Vector3(fmod(i * 3.7, 14.0) - 7.0, 0.9, fmod(i * 2.3, 8.0) - 4.0)
		stage.add_child(rig)
		for player: AnimationPlayer in rig.find_children("*", "AnimationPlayer", true, false):
			var clip := "Walk" if player.has_animation("Walk") else player.get_animation_list()[0]
			player.play(clip)
	Engine.max_fps = 0
	for threshold: float in [0.0, 1.0]:
		root.mesh_lod_threshold = threshold
		for i in 5:
			await process_frame
		var primitives := 0.0
		var start := Time.get_ticks_usec()
		for i in FRAMES:
			await process_frame
			primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var ms := (Time.get_ticks_usec() - start) / 1000.0 / FRAMES
		print("RESULT n=%d d=%.0fm lod=%s frame_ms=%.2f fps=%.1f triangles=%d" % [count, distance, "on" if threshold > 0.0 else "off", ms, 1000.0 / ms, int(primitives / FRAMES)])
	quit()
