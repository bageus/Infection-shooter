extends SceneTree
## Renders an infected hit several times so the baked blood mask is visible on
## the skin. Each shot is painted once into the mask (body_blood_bake.gd).
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_body_blood_bake.gd -- <out_dir>
##
## Writes <out_dir>/hits_1.png (one shot) and <out_dir>/hits_6.png (six shots).

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const SHOTS := [Vector3(-0.25, 1.25, -0.35), Vector3(0.2, 1.0, -0.35), Vector3(0.0, 1.45, -0.35), Vector3(0.3, 0.7, -0.3), Vector3(-0.3, 0.8, -0.3), Vector3(0.05, 1.1, -0.4)]

var _out_dir := "/tmp/body_blood_bake"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := _stage()
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = Vector3(0, 1, 0)
	await process_frame
	await process_frame
	enemy.get_node("DeathCloud").hide()
	var camera := Camera3D.new()
	camera.fov = 45.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(-1.1, 1.7, -2.3), Vector3(0, 1.1, 0), Vector3.UP)
	camera.make_current()
	var shot := 0
	for count in [1, 6]:
		while shot < count:
			var at: Vector3 = enemy.global_position + SHOTS[shot]
			enemy.call("take_projectile_damage", 2.0, at, Vector3(0, 0, 1), "PISTOL")
			shot += 1
			await process_frame
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out_dir.path_join("hits_%d.png" % count))
	quit(0)


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(12, 1, 12)
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.08, 0.09)
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
	return stage
