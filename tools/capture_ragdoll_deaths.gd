extends SceneTree
## Renders ragdoll deaths (ADR-0041) as frame sequences for visual review.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_ragdoll_deaths.gd -- <out_dir>
##
## Writes <out_dir>/<case>_<n>.png: run_pistol, close_shotgun, standing, table.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const FRAME_TIMES := [0.0, 0.25, 0.55, 1.0, 2.0]
const CASES := ["run_pistol", "close_shotgun", "standing", "table"]

var _out_dir := "/tmp/ragdoll_deaths"


class FakeTarget:
	extends Node3D
	func take_damage(_amount: float, _kind: String = "physical") -> void:
		pass


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for label: String in CASES:
		var stage := _stage()
		if label == "table":
			_box(stage, Vector3(0, 0.375, -1.2), Vector3(2.4, 0.75, 0.8), Color(0.45, 0.32, 0.2))
		var enemy := HUNGER.instantiate() as CharacterBody3D
		stage.add_child(enemy)
		enemy.global_position = Vector3(0, 1, 0)
		var target := FakeTarget.new()
		stage.add_child(target)
		target.global_position = Vector3(0, 1, -1.5)
		enemy.call("set_target", target)
		await process_frame
		await process_frame
		var camera := Camera3D.new()
		camera.fov = 50.0
		stage.add_child(camera)
		camera.look_at_from_position(Vector3(3.6, 1.8, 0.4), Vector3(0, 0.5, -0.5), Vector3.UP)
		camera.make_current()
		match label:
			"run_pistol", "table":
				enemy.velocity = Vector3(0, 0, -5.4)
				enemy.call("take_projectile_damage", 1000.0, enemy.global_position, Vector3(0, 0, 1), "PISTOL")
			"close_shotgun":
				enemy.call("take_projectile_damage", 1000.0, enemy.global_position, Vector3(0, 0, 1), "SHOTGUN")
			_:
				enemy.call("take_projectile_damage", 1000.0, enemy.global_position, Vector3(0, 0, 1), "PISTOL")
		enemy.get_node("DeathCloud").hide()
		var elapsed := 0.0
		for index in FRAME_TIMES.size():
			await create_timer(float(FRAME_TIMES[index]) - elapsed + 0.001).timeout
			elapsed = float(FRAME_TIMES[index])
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_out_dir.path_join("%s_%d.png" % [label, index]))
		stage.queue_free()
		await process_frame
	quit(0)


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	_box(stage, Vector3(0, -0.5, 0), Vector3(14, 1, 14), Color(0.32, 0.33, 0.35))
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


func _box(stage: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box_mesh.material = material
	mesh.mesh = box_mesh
	body.add_child(mesh)
	stage.add_child(body)
	body.position = at
