extends SceneTree

# Renders the kick and the left-hand jab from the side: godot --path . --script tools/capture_melee_strike.gd -- <out_dir>
const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")
const POSES := [[&"kick", 0.3], [&"kick", 0.5], [&"kick", 0.9], [&"punch", 0.3], [&"punch", 0.45], [&"punch", 0.6]]


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
	camera.position = Vector3(3.0, 0.9, 0.0)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
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
	var images: Array[Image] = []
	for pose: Array in POSES:
		driver.call("play_strike", pose[0])
		var duration: float = driver.strike.call("start", pose[0])
		driver.strike.set("_elapsed", float(pose[1]) * duration - 0.016)
		await process_frame
		await process_frame
		images.append(root.get_viewport().get_texture().get_image())
	var strip := Image.create(400 * POSES.size(), 500, false, Image.FORMAT_RGBA8)
	for index in images.size():
		strip.blit_rect(images[index], Rect2i(440, 110, 400, 500), Vector2i(400 * index, 0))
	strip.save_png(out_dir.path_join("melee_strike_poses.png"))
	print("Melee strike poses written to %s" % out_dir)
	quit(0)
