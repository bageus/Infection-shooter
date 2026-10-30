extends SceneTree
## Renders the emergency key, DNA and weapon pickups with their markers.
## xvfb-run godot --path . --script res://tools/capture_pickup_beacons.gd -- /out/dir
const KEY := preload("res://game/features/pickups/public/mission_key.gd")
const DNA := preload("res://game/bootstrap/app/tests/fixtures/test_dna_pickup.gd")
const WEAPON := preload("res://game/features/pickups/public/weapon_pickup.gd")
var _out := ""


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.45, 0.5, 0.55)
	plane.material = floor_material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	stage.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.07, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	stage.add_child(env)
	var key := KEY.new()
	stage.add_child(key)
	key.global_position = Vector3(-2.2, 0.25, 0)
	var dna := DNA.new()
	stage.add_child(dna)
	dna.position = Vector3(0, 0.5, 0)
	var weapon := WEAPON.new()
	weapon.weapon_index = 3
	stage.add_child(weapon)
	weapon.global_position = Vector3(2.2, 0.25, 0)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 2.2, 4.8)
	camera.look_at(Vector3(0, 0.9, 0))
	for frame in [0, 1]:
		for i in 25:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(_out.path_join("pickups_%d.png" % frame))
	quit()
