extends SceneTree
## Captures the quest target marker above a crate at several moments of its animation.
## Run under xvfb with a real renderer: ... --script tools/capture_objective_marker.gd -- <output dir> <prefix>

const SHOT_TIMES := [0.2, 0.6, 1.0, 1.5]
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://objective_marker"
	var prefix: String = args[1] if args.size() > 1 else "marker"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(640, 480)
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.32, 0.34, 0.38)
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var crate := Node3D.new()
	crate.name = "Crate"
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.9, 0.9, 0.9)
	box.mesh = box_mesh
	box.position.y = 0.45
	var box_material := StandardMaterial3D.new()
	box_material.albedo_color = Color(0.55, 0.4, 0.25)
	box.material_override = box_material
	crate.add_child(box)
	stage.add_child(crate)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	stage.add_child(sun)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.rotation_degrees = Vector3(-37, 0, 0)
	camera.position = Vector3(0, 3.6, 4.6)
	camera.fov = 40.0
	var marker := TARGET.new_marker()
	crate.add_child(marker)
	crate.set_meta(&"planning_tutorial_revealed", true)
	var elapsed := 0.0
	for time in SHOT_TIMES:
		await create_timer(time - elapsed).timeout
		elapsed = time
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir.path_join("%s_%.1fs.png" % [prefix, time]))
	quit(0)
