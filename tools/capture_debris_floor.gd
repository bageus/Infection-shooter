extends SceneTree
## Renders the largest file cabinet before it breaks and shortly after, from a low angle with the floor in view.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_debris_floor.gd -- <out_dir> <suffix>
##
## Writes file_cabinet_largest_floor_before.png (suffix "before") or _<suffix>_<seconds>.png after the break.

const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MODEL := "res://models/objects/enviroments/03/03_file_cabinet_largest.glb"
const FLOOR_TOP := 0.0135
var _out_dir := "/tmp/destruction_review"
var _suffix := "after"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_suffix = args[1]
	call_deferred("_capture")


func _capture() -> void:
	seed(7)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := Node3D.new()
	root.add_child(stage)
	_add_world(stage)
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", MODEL)
	prop.collision_mask = 3
	stage.add_child(prop)
	prop.global_position = Vector3(0, FLOOR_TOP, 0)
	prop.call("configure_world", effects, null)
	var camera := Camera3D.new()
	camera.fov = 50.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(1.6, 0.35, 2.4), Vector3(0, 0.25, 0), Vector3.UP)
	camera.make_current()
	await create_timer(0.5).timeout
	await _save("file_cabinet_largest_floor_before.png")
	for i in 14:
		if not is_instance_valid(prop) or prop.collision_layer == 0:
			break
		prop.call("take_projectile_hit", 400.0, prop.global_position + Vector3(0, 0.4, 0), Vector3.UP, Vector3(0.3, 0.0, -1.0).normalized(), "GRENADE")
		await create_timer(0.05).timeout
	await create_timer(0.55).timeout
	await _save("file_cabinet_largest_floor_%s_0_6s.png" % _suffix)
	await create_timer(0.9).timeout
	await _save("file_cabinet_largest_floor_%s.png" % _suffix)
	quit(0)


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(file_name))


func _add_world(stage: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = FLOOR_TOP - 0.1
	stage.add_child(floor_body)
	var floor_mesh := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(30, 0.025, 30)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.38, 0.42)
	slab.material = material
	floor_mesh.mesh = slab
	floor_mesh.position.y = FLOOR_TOP - 0.0125
	stage.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.82, 0.84, 0.88)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.82, 0.86)
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
