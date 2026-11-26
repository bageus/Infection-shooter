extends SceneTree
## Side-view frames of a spawned enemy climbing out of its hole (the floor plane hides what is still under it).
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --fixed-fps 30 --script res://tools/capture_enemy_climb.gd -- <out_dir> <brute|colossus|titan|revenant|hunger>
##
## Writes <enemy>_climb_NN.png (every 3rd physics frame) and logs the body height and the health-bar gate.

const SIZE := Vector2i(540, 540)
const EVERY := 3
const SHOTS := 44

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
	var stage := Node3D.new()
	root.add_child(stage)
	_build_stage(stage)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.position = Vector3(0, 0.1, -60.0)
	var enemy := (load("res://game/features/infected/public/infected_%s.tscn" % enemy_name) as PackedScene).instantiate() as CharacterBody3D
	enemy.set_meta(&"spawned_by", "hole")
	enemy.transform = Transform3D(Basis(), Vector3.ZERO)
	stage.add_child(enemy)
	enemy.call("set_target", target)
	var shot := 0
	var frame := 0
	while shot < SHOTS:
		await physics_frame
		frame += 1
		if frame % EVERY != 0:
			continue
		var at := Vector3(0, 0.9, enemy.global_position.z)
		_camera.look_at_from_position(at + Vector3(6.0, 0.0, 0.0), at)
		await RenderingServer.frame_post_draw
		var body := enemy.get_node("Body") as Node3D
		print("frame %3d y=%.2f z=%.2f emerging=%s clip=%s body_visible=%s body_y=%.2f" % [frame, enemy.global_position.y, enemy.global_position.z, enemy.get("_emerge_left"), enemy.get_node("AnimationDriver").get("_current"), body.is_visible_in_tree(), body.global_position.y])
		root.get_viewport().get_texture().get_image().save_png("%s/%s_climb_%02d.png" % [out_dir, enemy_name, shot])
		shot += 1
	print("done")
	quit(0)


func _build_stage(stage: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.52, 0.55)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.65, 0.68)
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	stage.add_child(light)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	stage.add_child(floor_body)
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
	stage.add_child(plane)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 50.0
	stage.add_child(_camera)
