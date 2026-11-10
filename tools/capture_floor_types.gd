extends SceneTree
## Review sheet: tile and concrete floor with biomass patches, floor scuffs and a wall base shadow.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_floor_types.gd -- <out_dir>
##
## Writes <out_dir>/floor_tile.png and <out_dir>/floor_concrete.png.

const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const WALL := preload("res://game/presentation/office_floor/public/structural/wall_straight.tscn")
var _out_dir := "/tmp/floor_types"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1200, 700)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.03, 0.03, 0.04)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.4, 0.42, 0.46)
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.0
	stage.add_child(sun)
	var floor_view := Node3D.new()
	floor_view.set_script(FLOOR)
	floor_view.set("floor_size", Vector2(16, 12))
	stage.add_child(floor_view)
	for x in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		var wall := WALL.instantiate() as Node3D
		wall.position = Vector3(x, 0, -3.0)
		stage.add_child(wall)
	for entry in [["biomass_02", Vector3(-1.5, 0, 0.5), 0.0], ["biomass_05", Vector3(-0.9, 0, 0.8), 0.7], ["biomass_04", Vector3(2.2, 0, 0.0), -0.5]]:
		var piece := DECAL.instantiate() as Node3D
		piece.call("configure_blood", entry[0], "floor")
		stage.add_child(piece)
		piece.position = (entry[1] as Vector3) + Vector3(0, 0.01, 0)
		piece.rotation.y = entry[2]
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.fov = 50.0
	camera.look_at_from_position(Vector3(0.0, 4.2, 4.5), Vector3(0.0, 0.0, -0.5))
	for type in ["tile", "concrete"]:
		floor_view.call("set_floor_type", type)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for i in 14:
			floor_view.call("stamp_floor_surface", Vector2(rng.randf_range(-5, 5), rng.randf_range(-2, 3)), "floor_scuff", rng.randi_range(0, 3), 0.9, rng.randi_range(0, 3))
		for i in 90:
			await process_frame
			OS.delay_msec(15)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out_dir.path_join("floor_%s.png" % type))
	quit()
