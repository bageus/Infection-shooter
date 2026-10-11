extends SceneTree
## Renders a mutagen death cloud from the game camera at several moments of
## its life for visual review.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_mutagen_cloud.gd -- <out_dir>
##
## Writes <out_dir>/mutagen_<seconds>.png for each moment. With a second
## argument "sequence" it writes 36 frames at 12 fps from the second second
## instead (<out_dir>/seq_<n>.png), to review the animation.

const CLOUD := preload("res://game/features/infection_source/public/mutagen_cloud.tscn")
const MOMENTS := [0.4, 0.8, 1.2, 1.6, 2.4, 4.0, 7.0, 10.0]
const GAME_EYE := Vector3(10, 12, 10) * 0.45

var _out_dir := "/tmp/mutagen_cloud"
var _sequence := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	_sequence = args.size() > 1 and args[1] == "sequence"
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.3, 0.31, 0.33)
	plane.material = floor_material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06, 0.07, 0.09)
	environment.environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	environment.environment.ambient_light_energy = 0.4
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.fov = 50.0
	stage.add_child(camera)
	camera.look_at_from_position(GAME_EYE, Vector3(0, 0.8, 0), Vector3.UP)
	camera.make_current()
	seed(7)
	var cloud := CLOUD.instantiate() as Area3D
	stage.add_child(cloud)
	cloud.call("activate")
	if _sequence:
		await create_timer(2.0).timeout
		for index in 36:
			await create_timer(1.0 / 12.0).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_out_dir.path_join("seq_%02d.png" % index))
		quit(0)
		return
	var elapsed := 0.0
	for moment: float in MOMENTS:
		await create_timer(moment - elapsed).timeout
		elapsed = moment
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out_dir.path_join("mutagen_%04.1f.png" % moment))
	quit(0)
