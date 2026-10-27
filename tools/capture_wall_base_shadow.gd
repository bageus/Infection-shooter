extends SceneTree
## Renders a wall corner with and without the baked wall base shadow strips.
## Run: xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/capture_wall_base_shadow.gd -- out_dir

const WALL := preload("res://game/presentation/office_floor/public/structural/wall_straight.tscn")
const SHADOW_QUALITY := preload("res://game/bootstrap/app/menu/shadow_quality.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "."
	root.size = Vector2i(900, 520)
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.45, 0.47, 0.5)
	plane.material = floor_material
	floor_mesh.position.y = 0.0135
	stage.add_child(floor_mesh)
	for spec in [[Vector3(0, 0, 0), 0.0], [Vector3(2, 0, 0), 0.0], [Vector3(4, 0, 0), 0.0], [Vector3(5.15, 0, 1.15), PI * 0.5], [Vector3(5.15, 0, 3.15), PI * 0.5]]:
		var wall := WALL.instantiate() as Node3D
		wall.position = spec[0]
		wall.rotation.y = spec[1]
		stage.add_child(wall)
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.06, 2.8, 0.3)
		var wall_material := StandardMaterial3D.new()
		wall_material.albedo_color = Color(0.6, 0.62, 0.68)
		mesh.material = wall_material
		box.mesh = mesh
		box.position.y = 1.4
		wall.add_child(box)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.shadow_enabled = false
	stage.add_child(sun)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(3.0, 5.0, 6.0), Vector3(3.0, 0.0, 0.5))
	camera.current = true
	for state in ["before", "after"]:
		SHADOW_QUALITY.apply(self, state == "before", 2)
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png("%s/wall_base_shadow_%s.png" % [out, state])
	quit()
