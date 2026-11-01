extends SceneTree

# Renders the kick key poses from the side and from the front-quarter: godot --path . --script tools/capture_melee_strike.gd -- <out_dir>
const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")
const POSES := [[&"kick", 0.1], [&"kick", 0.25], [&"kick", 0.45], [&"kick", 0.55], [&"kick", 0.75], [&"kick", 0.9]]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var stage := Node3D.new()
	root.add_child(stage)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 40, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	var character := CharacterBody3D.new()
	stage.add_child(character)
	var body := MODEL.instantiate() as Node3D
	body.name = "Body"
	character.add_child(body)
	var driver := DRIVER.new()
	driver.name = "AnimationDriver"
	driver.configure_clip_selector(func() -> StringName: return &"Idle_Pistol_TwoHand")
	character.add_child(driver)
	root.size = Vector2i(1280, 720)
	await process_frame
	# Frozen time: each pose is held exactly at its share of the strike.
	Engine.time_scale = 0.0
	var images: Array[Image] = []
	for view: Vector3 in [Vector3(3.2, 0.8, 0.0), Vector3(2.3, 0.9, 2.3)]:
		camera.position = view
		camera.look_at(Vector3(0, 0.75, 0.35))
		for pose: Array in POSES:
			driver.call("play_strike", pose[0])
			var duration: float = driver.strike.call("start", pose[0])
			for frame in 3:
				driver.strike.set("_elapsed", float(pose[1]) * duration)
				await process_frame
			images.append(root.get_viewport().get_texture().get_image())
	Engine.time_scale = 1.0
	var strip := Image.create(400 * POSES.size(), 1200, false, Image.FORMAT_RGBA8)
	for index in images.size():
		strip.blit_rect(images[index], Rect2i(400, 60, 400, 600), Vector2i(400 * (index % POSES.size()), 600 * (index / POSES.size())))
	strip.save_png(out_dir.path_join("kick_poses.png"))
	print("Melee strike poses written to %s" % out_dir)
	quit(0)
