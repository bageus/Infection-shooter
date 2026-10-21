extends SceneTree
## Renders two overlapping PlannerLights, once with equal and once with unequal
## brightness, to check that the light pools blend without visible rims.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_lamp_blend.gd -- <out_dir> <tag>
##
## Writes <out_dir>/lamp_blend_<tag>_{equal,unequal}.png.

const LAMP := preload("res://game/presentation/office_floor/public/props/planner_light.tscn")
const LIGHTING := preload("res://game/bootstrap/app/planning_lighting.gd")

var _out_dir := "/tmp/lighting_review"
var _tag := "after"
var _stage: Node3D
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_tag = args[1]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for case in [["equal", 3.0, 3.0], ["unequal", 3.0, 1.0]]:
		_new_stage()
		_floor(12.0)
		_lamp("point", Vector3(-1.8, 2.8, 0.0), case[1])
		_lamp("point", Vector3(1.8, 2.8, 0.0), case[2])
		_look(Vector3(0, 9.5, 6.5), Vector3(0, 0, 0))
		await _shot(case[0])
	quit()


func _new_stage() -> void:
	if _stage != null:
		_stage.free()
	_stage = Node3D.new()
	root.add_child(_stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.02, 0.025, 0.04)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	environment.environment.ambient_light_energy = 0.06
	_stage.add_child(environment)
	var lighting := LIGHTING.new()
	lighting.name = "PlanningLighting"
	_stage.add_child(lighting)
	lighting.setup(environment)
	lighting.set_local_lights_enabled(true)
	lighting.set_shadows_allowed(not OS.get_cmdline_user_args().has("noshadow"))
	# The game's overhead directional light at its dimmed look.
	var sun := DirectionalLight3D.new()
	sun.name = "GlobalOverheadLight"
	sun.rotation_degrees = Vector3(-60, 20, 0)
	sun.light_energy = 0.12
	sun.shadow_enabled = true
	_stage.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_stage.add_child(_camera)


func _floor(size: float) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size * 2.0, size * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.61, 0.63)
	plane.material = material
	mesh.mesh = plane
	_stage.add_child(mesh)


func _lamp(shape: String, pos: Vector3, energy: float) -> void:
	var lamp := LAMP.instantiate() as Node3D
	lamp.position = pos
	_stage.add_child(lamp)
	lamp.call("configure_fixture", shape, true)
	lamp.call("set_authored_energy", energy)
	lamp.call("set_local_lighting_enabled", true)


func _look(from: Vector3, target: Vector3) -> void:
	_camera.position = from
	_camera.look_at(target)
	_camera.current = true


func _shot(name: String) -> void:
	for i in range(8):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/lamp_blend_%s_%s.png" % [_out_dir, _tag, name])
	print("saved ", name)
