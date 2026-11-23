extends SceneTree
## Captures Hunger, Brute and Revenant in every costume skin (front, back) into one contact sheet per enemy.
## usage: xvfb-run godot --path . --script res://tools/capture_enemy_costumes.gd -- <output dir>
const SCENES := {
	"hunger": preload("res://game/features/infected/public/infected_hunger.tscn"),
	"brute": preload("res://game/features/infected/public/infected_brute.tscn"),
	"revenant": preload("res://game/features/infected/public/infected_revenant.tscn"),
}
const SKINS := ["normal", "no_tie", "janitor", "guard", "scientist", "hazmat"]
const CELL := Vector2i(300, 520)
var output := "user://costume_review"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for label: String in SCENES:
		var sheet := Image.create(CELL.x * SKINS.size(), CELL.y * 2, false, Image.FORMAT_RGBA8)
		for column in SKINS.size():
			for row in 2:
				var image := await _shot(SCENES[label], SKINS[column], row == 1)
				sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(column * CELL.x, row * CELL.y))
		sheet.save_png(output.path_join("%s_costumes.png" % label))
	quit()


func _shot(scene: PackedScene, skin: String, back: bool) -> Image:
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
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.make_current()
	var side := 1.0 if back else -1.0
	camera.look_at_from_position(Vector3(0.0, 1.0, side * 3.0), Vector3(0, 0.85, 0))
	camera.fov = 38
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	return image
