extends SceneTree
## Floor blood visibility at gameplay camera distance: a 6 x 6 grid of baked floor
## tiles seen from the zoomed-out player camera (24 m, about 37 degrees down). Prints
## how many tiles inside the view are drawn, then saves a frame.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_blood_floor_distance.gd -- <out_dir>
##
## Writes <out_dir>/floor_distance.png.

const BAKE := preload("res://game/presentation/office_floor/blood_floor_bake.gd")
const STAMP := preload("res://game/presentation/office_floor/blood_floor_stamp.gd")
var _out_dir := "/tmp/blood_floor_distance"


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
	environment.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	stage.add_child(environment)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.55, 0.55, 0.57)
	plane.material = paint
	floor_mesh.mesh = plane
	floor_mesh.layers = 1 | 128
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.fov = 75.0
	camera.position = Vector3(0, 14.4, 19.2)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var bake := BAKE.new() as Node3D
	bake.set("settings", {"decal": false, "visual_mask": 128, "quad_offset": 0.018})
	stage.add_child(bake)
	var texture := _texture()
	for x in range(-3, 3):
		for z in range(-3, 3):
			var at := Vector3((x + 0.5) * STAMP.TILE_METERS, 0.0, (z + 0.5) * STAMP.TILE_METERS)
			bake.call("stamp", texture, Color.WHITE, Vector2(2.4, 1.2), at, Basis.IDENTITY)
	await create_timer(8.0).timeout
	var live: Array = bake.call("_live_cells")
	var inside := 0
	var inside_live := 0
	for x in range(-3, 3):
		for z in range(-3, 3):
			var cell := Vector2i(x, z)
			var center := Vector3((x + 0.5) * STAMP.TILE_METERS, 0.0, (z + 0.5) * STAMP.TILE_METERS)
			if camera.is_position_in_frustum(center):
				inside += 1
				if live.has(cell):
					inside_live += 1
	print("Tiles in view: %d; drawn: %d of %d in view; drawn in total: %d" % [inside, inside_live, inside, live.size()])
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join("floor_distance.png"))
	quit(0)


func _texture() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var distance := Vector2(x - 32, y - 32).length() / 32.0
			image.set_pixel(x, y, Color(0.5, 0.02, 0.01, clampf(1.0 - distance, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)
