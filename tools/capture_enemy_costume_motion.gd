extends SceneTree
## Captures every costume of Hunger, Brute and Revenant mid-animation: one sheet per enemy, one row per clip frame.
## usage: xvfb-run godot --path . --script res://tools/capture_enemy_costume_motion.gd -- <output dir>
const SCENES := {
	"hunger": preload("res://game/features/infected/public/infected_hunger.tscn"),
	"brute": preload("res://game/features/infected/public/infected_brute.tscn"),
	"revenant": preload("res://game/features/infected/public/infected_revenant.tscn"),
}
const SKINS := ["janitor", "guard", "scientist", "hazmat"]
## [clip, time in seconds]
const FRAMES := [["Walk", 0.2], ["Walk", 0.6], ["AttackLeft", 0.35], ["AttackRight", 0.35], ["DeathForward", 0.5], ["DeathForward", 1.0], ["DeathBack", 0.6]]
const CELL := Vector2i(300, 420)
var output := "user://costume_motion"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for label: String in SCENES:
		var sheet := Image.create(CELL.x * SKINS.size(), CELL.y * FRAMES.size(), false, Image.FORMAT_RGBA8)
		for column in SKINS.size():
			for row in FRAMES.size():
				var image := await _shot(SCENES[label], SKINS[column], FRAMES[row][0], FRAMES[row][1])
				sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(column * CELL.x, row * CELL.y))
		sheet.save_png(output.path_join("%s_motion.png" % label))
	quit()


func _shot(scene: PackedScene, skin: String, clip: String, time: float) -> Image:
	var viewport := SubViewport.new()
	viewport.size = CELL
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.3, 0.3, 0.33)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	stage.add_child(sun)
	var actor := scene.instantiate() as CharacterBody3D
	actor.set_meta(&"skin", skin)
	stage.add_child(actor)
	actor.set_physics_process(false)
	var player := actor.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.play(clip)
	player.seek(time, true)
	player.pause()
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.make_current()
	var deaths := clip.begins_with("Death")
	camera.look_at_from_position(Vector3(1.2, 1.3 if not deaths else 1.6, -2.9), Vector3(0, 0.7 if not deaths else 0.3, 0))
	camera.fov = 40
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	return image
