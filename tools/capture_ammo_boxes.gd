extends SceneTree
## Renders the supply ammo boxes side by side at their in-game size.
## xvfb-run godot --path . --script res://tools/capture_ammo_boxes.gd -- /out/dir
const BOXES := [
	"res://game/features/pickups/public/ammo_pistol_pickup.tscn",
	"res://game/features/pickups/public/ammo_uzi_pickup.tscn",
	"res://game/features/pickups/public/ammo_shotgun_pickup.tscn",
	"res://game/features/pickups/public/ammo_automate_pickup.tscn",
	"res://game/features/pickups/public/ammo_sniper_pickup.tscn",
	"res://game/features/pickups/public/ammo_minigun_pickup.tscn",
]
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
	for index in BOXES.size():
		var box := (load(BOXES[index]) as PackedScene).instantiate() as Node3D
		stage.add_child(box)
		box.position = Vector3(-2.25 + index * 0.9, 0.0, 0.0)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 1.5, 2.3)
	camera.look_at(Vector3(0, 0.0, 0))
	for i in 25:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(_out.path_join("ammo_boxes.png"))
	quit()
