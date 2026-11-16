extends SceneTree
## Side-view frames of an enemy chasing: a window while it walks and one while it runs.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --fixed-fps 30 --script res://tools/capture_enemy_walk.gd -- <out_dir> <brute|colossus|titan|revenant|hunger>
##
## Writes <enemy>_walk_NN.png / <enemy>_run_NN.png (every 3rd frame, 12 each).
## Logs the clip and speed so the windows can be checked.

const SIZE := Vector2i(720, 540)
const EVERY := 3
const SHOTS := 12

var _stage: Node3D
var _camera: Camera3D


class FakeTarget:
	extends Node3D
	func take_damage(_amount: float, _kind: String = "physical") -> void:
		pass


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var enemy_name: String = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = SIZE
	_build_stage()
	var target := FakeTarget.new()
	_stage.add_child(target)
	target.position = Vector3(0, 0.1, -60.0)
	var enemy := (load("res://game/features/infected/public/infected_%s.tscn" % enemy_name) as PackedScene).instantiate() as CharacterBody3D
	_stage.add_child(enemy)
	enemy.position = Vector3(0, 1.05, 0)
	enemy.call("set_target", target)
	var driver := enemy.get_node("AnimationDriver")
	# The AI is bypassed: the body is walked straight at the gameplay speed of each gait.
	enemy.set_physics_process(false)
	var scale_y: float = enemy.get_node("Body").scale.y
	var half: float = (enemy.get_node("CollisionShape3D").shape as CapsuleShape3D).height * 0.5 + 0.02
	for kind: String in ["walk", "run"]:
		var speed: float = driver.get("%s_reference_speed" % kind)
		enemy.position = Vector3(0, half, 0)
		var frame := 0
		var taken := 0
		while taken < SHOTS:
			await physics_frame
			frame += 1
			enemy.velocity = Vector3(0, 0, -speed)
			enemy.position.z -= speed / 30.0
			if frame < 20 or frame % EVERY != 0:
				continue
			if frame == 21:
				print(enemy_name, " ", kind, " clip ", driver.get("_current"), " speed ", speed)
			var at: Vector3 = enemy.global_position + Vector3(0, 0.9 * scale_y, 0)
			_camera.look_at_from_position(at + Vector3(7.0 * scale_y, 0.0, 0), at)
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%s_%02d.png" % [out_dir, enemy_name, kind, taken])
			taken += 1
	print("done")
	quit(0)


func _build_stage() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.52, 0.55)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.65, 0.68)
	var world := WorldEnvironment.new()
	world.environment = environment
	_stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_stage.add_child(light)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	_stage.add_child(floor_body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(400, 400)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.38, 0.4)
	mesh.material = material
	plane.mesh = mesh
	_stage.add_child(plane)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 60.0
	_stage.add_child(_camera)
