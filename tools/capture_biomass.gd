extends SceneTree
## Biomass review sheet (ADR-0061): the same overlapping patches drawn as
## separate relief meshes and as one fused mass, on a floor and on a wall.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_biomass.gd -- <out_dir>
##
## Writes <out_dir>/biomass_floor.png and <out_dir>/biomass_wall.png.

const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
var _out_dir := "/tmp/biomass"


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
	environment.environment.ambient_light_color = Color(0.25, 0.27, 0.32)
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	stage.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.22, 0.22, 0.24)
	floor_material.roughness = 0.35
	floor_mesh.mesh.surface_set_material(0, floor_material)
	stage.add_child(floor_mesh)
	var wall := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(14, 4, 0.2)
	wall.mesh = wall_box
	wall.position = Vector3(0, 2, -4)
	wall_box.material = floor_material
	stage.add_child(wall)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	# Left: every piece alone under its own parent; right: one shared parent, fused.
	var raw := _cluster(stage, Vector3(-1.5, 0, 0), false)
	var fused := _cluster(stage, Vector3(1.5, 0, 0), true)
	for i in 90:
		await process_frame
		OS.delay_msec(15)
	camera.fov = 45.0
	camera.position = Vector3(-1.5, 2.0, 1.4)
	camera.look_at(Vector3(-1.5, 0, 0.0))
	await _shot("biomass_floor_separate.png")
	camera.position = Vector3(1.5, 2.0, 1.4)
	camera.look_at(Vector3(1.5, 0, 0.0))
	await _shot("biomass_floor_fused.png")
	camera.position = Vector3(1.5, 1.7, -1.9)
	camera.look_at(Vector3(1.5, 1.6, -4))
	for piece: Node3D in fused:
		piece.position.y = 1.6
		piece.position.z = -3.88
		piece.rotation = Vector3(PI * 0.5, 0, 0)
	for piece: Node3D in raw:
		piece.position.y = 1.6
		piece.position.z = -3.88
		piece.rotation = Vector3(PI * 0.5, 0, 0)
	for i in 90:
		await process_frame
		OS.delay_msec(15)
	await _shot("biomass_wall_fused.png")
	camera.position = Vector3(-1.5, 1.7, -1.9)
	camera.look_at(Vector3(-1.5, 1.6, -4))
	await _shot("biomass_wall_separate.png")
	quit()


func _cluster(stage: Node3D, origin: Vector3, _fused: bool) -> Array[Node3D]:
	var pieces: Array[Node3D] = []
	for entry in [["biomass_02", Vector3(0, 0, 0), 0.0], ["biomass_05", Vector3(0.55, 0, 0.3), 0.7], ["biomass_04", Vector3(-0.5, 0, 0.55), -0.5], ["biomass_06", Vector3(0.1, 0, -0.7), 2.4]]:
		var piece := DECAL.instantiate() as Node3D
		piece.call("configure_blood", entry[0], "floor")
		# Pieces fuse with siblings only, so a private parent keeps one piece apart.
		var holder := stage
		if not _fused:
			holder = Node3D.new()
			stage.add_child(holder)
		holder.add_child(piece)
		piece.position = origin + (entry[1] as Vector3) + Vector3(0, 0.01, 0)
		piece.rotation.y = entry[2]
		pieces.append(piece)
	return pieces


func _shot(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(file_name))
