extends SceneTree
## Renders infected killed next to a table and walls for visual review of the
## obstacle-aware death falls.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_corpse_obstacles.gd -- <out_dir>
##
## Writes <out_dir>/<case>.png: on_table, wall_near, wall_far, wall_ahead,
## open_floor.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const CASES := {
	"on_table": [Vector3(0, 0.375, -1.0), Vector3(2.4, 0.75, 0.8)],
	"wall_near": [Vector3(0, 1.25, -1.15), Vector3(3, 2.5, 0.2)],
	"wall_far": [Vector3(0, 1.25, -1.55), Vector3(3, 2.5, 0.2)],
	"wall_ahead": [Vector3(0, 1.25, -0.6), Vector3(3, 2.5, 0.2)],
	"open_floor": [Vector3(0, -5, 0), Vector3(0.1, 0.1, 0.1)],
}

var _out_dir := "/tmp/corpse_obstacles"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var index := 0
	for label: String in CASES:
		var origin := Vector3(index * 20.0, 0, 0)
		index += 1
		var stage := _stage(origin)
		var obstacle: Array = CASES[label]
		_box(stage, origin + obstacle[0], obstacle[1], 1, Color(0.45, 0.32, 0.2))
		var enemy := HUNGER.instantiate() as CharacterBody3D
		stage.add_child(enemy)
		enemy.global_position = origin + Vector3(0, 1, 0)
		await process_frame
		await process_frame
		enemy.velocity = Vector3(0, 0, -5.4)
		enemy.call("take_projectile_damage", 1000.0, enemy.global_position, Vector3(0, 0, 1), "PISTOL")
		enemy.get_node("DeathCloud").hide() # Keep the body in view.
		var camera := Camera3D.new()
		camera.fov = 50.0
		stage.add_child(camera)
		camera.look_at_from_position(origin + Vector3(3.2, 2.2, 0.6), origin + Vector3(0, 0.6, -0.7), Vector3.UP)
		camera.make_current()
		await create_timer(2.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out_dir.path_join(label + ".png"))
		stage.queue_free()
		await process_frame
	quit(0)


func _stage(origin: Vector3) -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	_box(stage, origin + Vector3(0, -0.5, 0), Vector3(12, 1, 12), 2, Color(0.32, 0.33, 0.35))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.08, 0.09)
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
	return stage


func _box(stage: Node3D, at: Vector3, size: Vector3, layer: int, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	cube.material = material
	mesh.mesh = cube
	body.add_child(mesh)
	stage.add_child(body)
	body.global_position = at
