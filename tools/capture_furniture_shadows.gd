extends SceneTree
## Renders a few pieces of office furniture under the game's overhead light,
## with and without their contact shadows, for visual review.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_furniture_shadows.gd -- <out_dir>
##
## Writes <out_dir>/furniture_shadows_on.png and furniture_shadows_off.png.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MODELS := [
	["res://models/objects/enviroments/07/07_table_longest.glb", Vector3(0, 0, 0), 0.0],
	["res://models/objects/enviroments/06/06_simple_chair.glb", Vector3(-1.2, 0, 1.1), PI],
	["res://models/objects/enviroments/06/06_conference_chair.glb", Vector3(0.6, 0, 1.2), PI],
	["res://models/objects/enviroments/03/03_file_cabinet_smaller.glb", Vector3(3.2, 0, -1.4), 0.0],
	["res://models/objects/enviroments/07/07_round_dining_table.glb", Vector3(-3.4, 0, -0.6), 0.0],
	["res://models/objects/enviroments/10/10_beanbag_green.glb", Vector3(3.0, 0, 1.6), 0.0],
	["res://models/objects/enviroments/09/09_trash_bin.glb", Vector3(-2.2, 0, 1.9), 0.0],
]

var _out_dir := "/tmp/furniture_shadows"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 0.2, 30)
	shape.shape = box
	shape.position.y = -0.1 + 0.0135
	floor_body.add_child(shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.55, 0.56, 0.58)
	plane.material = floor_material
	floor_mesh.mesh = plane
	floor_mesh.position.y = 0.0135
	floor_body.add_child(floor_mesh)
	stage.add_child(floor_body)
	# The game's overhead light and dim ambient (bootstrap/app/main.tscn).
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0.42261824, 0.9063078), Vector3(0, -0.9063078, 0.42261824)), Vector3.ZERO)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	stage.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.8, 0.4)
	lamp.omni_range = 8.0
	lamp.light_energy = 1.4
	stage.add_child(lamp)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.055, 0.075, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.62, 0.68, 0.78)
	environment.environment.ambient_light_energy = 0.35
	stage.add_child(environment)
	for entry: Array in MODELS:
		var prop := PROP.instantiate() as RigidBody3D
		prop.set("model_path", entry[0])
		prop.position = entry[1]
		prop.rotation.y = entry[2]
		prop.freeze = true
		stage.add_child(prop)
	var camera := Camera3D.new()
	camera.fov = 50.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(4.5, 6.5, 6.5), Vector3(0, 0.3, 0), Vector3.UP)
	camera.make_current()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join("furniture_shadows_on.png"))
	for node in stage.find_children("ContactShadow", "", true, false):
		(node as Node3D).hide()
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join("furniture_shadows_off.png"))
	quit(0)
