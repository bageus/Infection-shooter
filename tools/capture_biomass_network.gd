extends SceneTree
## Generated biomass review (ADR-0062): a small level with walls, a column and
## two spawn holes; the planner's generator lays the network and floor mass
## folds up the walls and stops at the level edge.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_biomass_network.gd -- <out_dir>
##
## Writes <out_dir>/network_top.png and <out_dir>/network_wall.png.

const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const GENERATOR := preload("res://game/bootstrap/app/biomass_generator.gd")
const LEVEL := Rect2(-9.0, -6.0, 18.0, 12.0)
const BOXES := [
	{"size": Vector3(0.3, 2.5, 7.0), "at": Vector3(0.0, 1.25, -2.5)},
	{"size": Vector3(0.8, 1.8, 0.8), "at": Vector3(-4.0, 0.9, 2.0)},
	{"size": Vector3(3.0, 0.9, 1.2), "at": Vector3(5.0, 0.45, 2.5)},
]
var _out_dir := "/tmp/biomass"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	call_deferred("_capture")


func _solid(point: Vector2) -> bool:
	for box: Dictionary in BOXES:
		var size: Vector3 = box["size"]
		var at: Vector3 = box["at"]
		if absf(point.x - at.x) < size.x * 0.5 + 0.3 and absf(point.y - at.z) < size.z * 0.5 + 0.3:
			return true
	return false


func _capture() -> void:
	root.size = Vector2i(1280, 800)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.1, 0.25, 0.5)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.45, 0.47, 0.5)
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 1.1
	stage.add_child(sun)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.72, 0.72, 0.74)
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = LEVEL.size
	plane.material = paint
	floor_node.mesh = plane
	stage.add_child(floor_node)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(LEVEL.size.x, 0.2, LEVEL.size.y)
	floor_shape.position.y = -0.1
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	for box: Dictionary in BOXES:
		var body := StaticBody3D.new()
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = box["size"]
		cube.material = paint
		mesh.mesh = cube
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		(collision.shape as BoxShape3D).size = box["size"]
		body.add_child(collision)
		stage.add_child(body)
		body.position = box["at"]
	var floor_view := Node3D.new()
	floor_view.set_script(preload("res://tools/capture_floor_stub.gd"))
	floor_view.set("floor_size", LEVEL.size)
	stage.add_child(floor_view)
	await process_frame
	await process_frame
	var holes := [Vector2(-6.5, -3.0), Vector2(6.5, 0.0)]
	var plan := GENERATOR.plan(LEVEL, holes, _solid, 0.6, 12)
	print("pieces: ", plan.size())
	for piece in plan:
		var node := DECAL.instantiate() as Node3D
		node.call("configure_blood", str(piece["texture"]), "floor")
		node.scale = Vector3.ONE * float(piece["scale"])
		stage.add_child(node)
		node.call("configure_floor_debris", floor_view)
		var at: Vector2 = piece["position"]
		node.position = Vector3(at.x, 0.0135, at.y)
		node.basis = Basis.from_euler(Vector3(0.0, float(piece["yaw"]), 0.0)).scaled(node.scale)
	var hand: Array[Node3D] = []
	# A few pieces placed by hand against the walls and past the level edge.
	for spec in [[Vector3(-0.35, 0.0135, -4.0), 0.0, 3.0], [Vector3(-4.0, 0.0135, 1.1), 1.0], [Vector3(8.8, 0.0135, -5.5), 0.5], [Vector3(5.0, 0.0135, 3.0), 0.3], [Vector3(0.4, 0.0135, -1.0), 1.2]]:
		var node := DECAL.instantiate() as Node3D
		node.call("configure_blood", "biomass_02", "floor")
		node.scale = Vector3.ONE * (float(spec[2]) if spec.size() > 2 else 1.5)
		stage.add_child(node)
		node.call("configure_floor_debris", floor_view)
		node.position = spec[0]
		node.basis = Basis.from_euler(Vector3(0.0, float(spec[1]), 0.0)).scaled(node.scale)
		hand.append(node)
	for _frame in 120:
		await process_frame
	for node in hand:
		print("fit ", node.position, " ", node.get("_clip_fit"))
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.fov = 50.0
	camera.position = Vector3(0, 17, 6)
	camera.look_at(Vector3(0, 0, 0))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_out_dir + "/network_top.png")
	camera.position = Vector3(-3.0, 2.2, -1.0)
	camera.look_at(Vector3(0, 0.5, -3.6))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_out_dir + "/network_wall.png")
	camera.position = Vector3(-6.5, 3.5, 5.5)
	camera.look_at(Vector3(-4.0, 0.7, 1.1))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_out_dir + "/network_column.png")
	quit()
