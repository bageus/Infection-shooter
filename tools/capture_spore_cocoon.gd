extends SceneTree
## Spore Cocoon placement against a wall, for visual review.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_spore_cocoon.gd -- <out_dir> <aim|floor>
##
## "aim" puts the cocoon where the aim ray met the wall (the old behaviour);
## "floor" puts it where Spore Cocoon now lands. Writes <out_dir>/<mode>.png.

const PLAYER := preload("res://game/features/player/public/player.tscn")
## The aim ray met the face of a wall, 1.4 m up.
const AIM_ON_WALL := Vector3(2.35, 1.4, 0.0)

var _out_dir := ""
var _mode := "floor"
var _stage: Node3D
var _player: CharacterBody3D
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -- <out_dir> <aim|floor>")
		quit(1)
		return
	_out_dir = args[0]
	_mode = args[1]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_build_stage()
	# Give the physics world a few frames to register the wall before any ray.
	await _wait(0.6)
	var effects: Node = _player.get("mutation_effects")
	var vfx: Node = effects.get("vfx")
	vfx.call("configure_world", _stage)
	var spot: Vector3 = AIM_ON_WALL if _mode == "aim" else effects.call("acid_floor_point", AIM_ON_WALL)
	print("Spore Cocoon (%s) at %s" % [_mode, spot])
	vfx.call("spore_cocoon", spot, 3.0, 2.0)
	await _shot(_mode, 1.6)
	quit(0)


func _build_stage() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	_add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40), Color(0.32, 0.33, 0.35))
	# A wall to the player's right, its face at x = 2.5.
	_add_box(Vector3(2.65, 1.5, 0), Vector3(0.3, 3, 6), Color(0.55, 0.56, 0.58))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.1
	_stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.08, 0.09)
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.environment.ambient_light_energy = 0.7
	_stage.add_child(environment)
	_player = PLAYER.instantiate() as CharacterBody3D
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_stage.add_child(_player)
	_player.set_physics_process(false)
	# The capsule origin sits 0.9 m above the feet, as in the game.
	_player.global_position = Vector3(0, 0.9, 0)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_stage.add_child(_camera)
	_camera.look_at_from_position(Vector3(-3.5, 2.6, 4.5), Vector3(1.0, 0.8, 0.0), Vector3.UP)
	_camera.make_current()


func _add_box(center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	_stage.add_child(body)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(label: String, delay: float) -> void:
	await _wait(delay)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(label + ".png"))
