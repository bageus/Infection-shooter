extends SceneTree
## Biomass edge review (ADR-0061): patches on a wall top, a wall corner and a
## wall foot, drawn without and with the edge fit.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_biomass_edges.gd -- <out_dir>
##
## Writes <out_dir>/edges_before.png and <out_dir>/edges_after.png.

const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const CLIP := preload("res://game/presentation/office_floor/biomass_clip.gd")
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
	environment.environment.ambient_light_color = Color(0.3, 0.32, 0.36)
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.2
	stage.add_child(sun)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.6, 0.6, 0.62)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	(floor_mesh.mesh as PlaneMesh).size = Vector2(30, 30)
	floor_mesh.mesh.surface_set_material(0, paint)
	stage.add_child(floor_mesh)
	# Wall A ends at x=2 (outer corner); wall B continues round it along z.
	var wall := _box(stage, Vector3(6, 2.0, 0.3), Vector3(-1, 1.0, 0), paint)
	_box(stage, Vector3(0.3, 2.0, 4), Vector3(1.85, 1.0, -2.15), paint)
	for body_box in [[Vector3(6, 2.0, 0.3), Vector3(-1, 1.0, 0)], [Vector3(0.3, 2.0, 4), Vector3(1.85, 1.0, -2.15)]]:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		(collision.shape as BoxShape3D).size = body_box[0]
		body.add_child(collision)
		stage.add_child(body)
		body.position = body_box[1]
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.fov = 50.0
	var pieces: Array[Node3D] = []
	for spec in [["biomass_02", Vector3(-3.0, 1.85, 0.15), 1.0], ["biomass_05", Vector3(1.9, 1.0, 0.15), 1.0], ["biomass_01", Vector3(0.0, 0.25, 0.15), 1.0]]:
		var piece := DECAL.instantiate() as Node3D
		piece.call("configure_blood", spec[0], "wall")
		stage.add_child(piece)
		piece.position = spec[1]
		piece.scale = Vector3.ONE * float(spec[2])
		piece.call("attach_blood", wall, "wall")
		pieces.append(piece)
	camera.position = Vector3(5.0, 3.0, 4.0)
	camera.look_at(Vector3(-0.5, 1.0, -0.5))
	for i in 40:
		await process_frame
	for piece in pieces:
		piece.set("_clip_stamp", [])
		piece.call("_clip_biomass")
	for i in 5:
		await process_frame
	for piece in pieces:
		CLIP.apply(piece.get("_visual"), {})
		piece.set_process(false)
	await _shot("edges_before.png")
	# The cached stamp would skip the refit.
	for piece in pieces:
		piece.set("_clip_stamp", [])
		piece.call("_clip_biomass")
	await _shot("edges_after.png")
	await _inner_corner_and_crate(stage, paint, camera)
	quit()


# Inner wall corner and a crate: edges_inner_*.png, edges_crate_*.png.
func _inner_corner_and_crate(stage: Node3D, paint: Material, camera: Camera3D) -> void:
	var base := Vector3(30, 0, 0)
	var wall := _box(stage, Vector3(6.2, 2.4, 0.2), base + Vector3(0.1, 1.2, 0), paint)
	_solid(stage, Vector3(0.2, 2.4, 3), base + Vector3(3.1, 1.2, 1.5), paint)
	var crate := _box(stage, Vector3(1.0, 0.8, 0.6), base + Vector3(-9, 1.0, 3), paint)
	_solid(stage, Vector3(1.0, 0.8, 0.6), base + Vector3(-9, 1.0, 3), null)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	(floor_mesh.mesh as PlaneMesh).size = Vector2(30, 30)
	floor_mesh.mesh.surface_set_material(0, paint)
	floor_mesh.position = base
	stage.add_child(floor_mesh)
	await physics_frame
	await physics_frame
	var pieces: Array[Node3D] = []
	for spec in [["biomass_02", base + Vector3(2.9, 1.2, 0.1), wall], ["biomass_05", base + Vector3(-9.35, 1.0, 3.3), crate], ["biomass_03", base + Vector3(-9.0, 1.35, 3.3), crate]]:
		var piece := DECAL.instantiate() as Node3D
		piece.call("configure_blood", spec[0], "wall")
		stage.add_child(piece)
		piece.position = spec[1]
		piece.scale = Vector3.ONE * (1.1 if spec[2] == wall else 0.7)
		piece.call("attach_blood", spec[2], "wall")
		pieces.append(piece)
	for view in [["inner", base + Vector3(0.0, 1.8, 3.2), base + Vector3(2.9, 1.2, 0.8)], ["crate", base + Vector3(-6.8, 2.0, 5.5), base + Vector3(-9.0, 1.0, 3.0)]]:
		camera.position = view[1]
		camera.look_at(view[2])
		for i in 40:
			await process_frame
		for piece in pieces:
			piece.set("_clip_stamp", [])
			piece.call("_clip_biomass")
		for i in 5:
			await process_frame
		for piece in pieces:
			CLIP.apply(piece.get("_visual"), {})
			piece.set_process(false)
		await _shot("edges_%s_before.png" % view[0])
		for piece in pieces:
			piece.set("_clip_stamp", [])
			piece.call("_clip_biomass")
		await _shot("edges_%s_after.png" % view[0])


func _solid(stage: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	(collision.shape as BoxShape3D).size = size
	body.add_child(collision)
	stage.add_child(body)
	body.position = at
	if material != null:
		_box(stage, size, at, material)


func _box(stage: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.mesh.size = size
	box.mesh.material = material
	box.position = at
	stage.add_child(box)
	return box


func _shot(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(file_name))
