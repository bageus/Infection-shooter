extends SceneTree
## Renders the lamp fixtures (point, linear, rectangle), a desk lamp, a wall with
## a column and an elevator door, for visual lighting review.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_lighting_review.gd -- <out_dir> <tag>
##
## Writes <out_dir>/lighting_<tag>_{lamps,wall,elevator_closed,elevator_open}.png.

const LAMP := preload("res://game/presentation/office_floor/public/props/planner_light.tscn")
const ELEVATOR := preload("res://game/presentation/office_floor/public/structural/elevator_door.tscn")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
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
	_new_stage()
	_floor(12.0)
	_lamp("point", Vector3(-3.0, 2.8, 0.0))
	_lamp("linear", Vector3(0.0, 2.8, 0.0), 0.0)
	_lamp("rectangle", Vector3(3.0, 2.8, 0.0))
	_look(Vector3(0, 9.5, 6.5), Vector3(0, 0, 0))
	await _shot("lamps")
	_new_stage()
	_floor(12.0)
	_box(Vector3(0.2, 3.0, 5.0), Vector3(0.0, 1.5, 0.0), Color(0.8, 0.8, 0.82))
	_box(Vector3(0.6, 3.0, 0.6), Vector3(-3.5, 1.5, -2.5), Color(0.8, 0.8, 0.82))
	_lamp("linear", Vector3(-0.9, 2.8, 0.0), PI * 0.5)
	_lamp("point", Vector3(-3.5, 2.8, -1.7))
	_look(Vector3(6.0, 8.0, 7.0), Vector3(-1.0, 0, -0.5))
	await _shot("wall")
	_new_stage()
	_floor(12.0)
	var desk := PROP.instantiate() as RigidBody3D
	desk.set("model_path", "res://models/objects/enviroments/05/05_lamp.glb")
	desk.position = Vector3(0, 0.33, 0)
	desk.freeze = true
	_stage.add_child(desk)
	desk.freeze = true
	_box(Vector3(1.6, 0.05, 0.8), Vector3(0, 0.0, 0), Color(0.55, 0.4, 0.25))
	_box(Vector3(0.3, 0.9, 0.05), Vector3(0.7, 0.45, -0.5), Color(0.7, 0.7, 0.72))
	_look(Vector3(0, 1.6, 2.6), Vector3(0, 0.3, 0))
	await _shot("desk_lamp")
	for open in [false, true]:
		_new_stage()
		_floor(12.0)
		var door := ELEVATOR.instantiate() as Node3D
		door.rotation.y = 0.0
		_stage.add_child(door)
		var actor := Node3D.new()
		actor.position = Vector3(0, 0, -0.8 if open else -9.0)
		_stage.add_child(actor)
		door.get_node("DoorController").call("configure_player", actor)
		_look(Vector3(0, 1.8, -5.5), Vector3(0, 1.8, 0))
		for i in range(90 if open else 5):
			await physics_frame
		await _shot("elevator_open" if open else "elevator_closed")
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


func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = pos
	_stage.add_child(mesh)


func _lamp(shape: String, pos: Vector3, yaw := 0.0) -> void:
	var lamp := LAMP.instantiate() as Node3D
	lamp.position = pos
	lamp.rotation.y = yaw
	_stage.add_child(lamp)
	lamp.call("configure_fixture", shape, true)
	lamp.call("set_authored_energy", 3.0)
	lamp.call("set_local_lighting_enabled", true)


func _look(from: Vector3, target: Vector3) -> void:
	_camera.position = from
	_camera.look_at(target)
	_camera.current = true


func _shot(name: String) -> void:
	for i in range(8):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/lighting_%s_%s.png" % [_out_dir, _tag, name])
	print("saved ", name)
