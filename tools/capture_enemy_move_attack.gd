extends SceneTree
## Frames for the review of enemy leg motion during a moving attack and of the
## Hunger's get-up from all fours.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --fixed-fps 30 --script res://tools/capture_enemy_move_attack.gd -- <out_dir> [scenario]
##
## Writes <scenario>_<NNN>.png every 2nd physics frame, and logs the frame of the
## event (attack call or posture change) so a contact sheet can be cut around it.
## Scenarios: attack_hunger, attack_brute (attack swung while chasing), rise.

const SCENES := {
	"attack_hunger": "res://game/features/infected/public/infected_hunger.tscn",
	"attack_brute": "res://game/features/infected/public/infected_brute.tscn",
	"rise": "res://game/features/infected/public/infected_hunger.tscn",
}
const SIZE := Vector2i(480, 360)
const EVERY := 2

var _out_dir := "/tmp/enemy_move_attack"
var _stage: Node3D
var _camera: Camera3D
var _subject: Node3D


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
	root.size = SIZE
	var only := OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	for scenario: String in SCENES:
		if only.is_empty() or only == scenario:
			await _play(scenario)
	quit(0)


func _play(scenario: String) -> void:
	_build_stage()
	var target := FakeTarget.new()
	_stage.add_child(target)
	target.position = Vector3(0, 0.1, -40.0)
	var enemy := (load(SCENES[scenario]) as PackedScene).instantiate() as CharacterBody3D
	_stage.add_child(enemy)
	enemy.position = Vector3(0, 0.1, 0)
	_subject = enemy
	if scenario == "rise":
		target.position = Vector3(0, 0.1, -16.0)
		enemy.set("_feral", true)
		enemy.call("watch_target", target)
		enemy.get("_senses").sight_range = 30.0
	else:
		enemy.call("set_target", target)
	await process_frame
	var posture = enemy.get("posture")
	for frame in 420 if scenario == "rise" else 240:
		if scenario != "rise" and frame == 70:
			print(scenario, " attack at ", frame / EVERY)
			enemy.get_node("AnimationDriver").call("play_one_shot", &"attack")
		await physics_frame
		if scenario == "rise" and enemy.get("posture") != posture:
			print(scenario, " posture ", posture, " -> ", enemy.get("posture"), " at ", frame / EVERY)
			posture = enemy.get("posture")
		if frame % EVERY == 0:
			var at := _subject.global_position + Vector3(0, 0.9, 0)
			_camera.look_at_from_position(at + Vector3(2.6, 1.5, 3.1), at)
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%03d.png" % [_out_dir, scenario, frame / EVERY])
	_stage.queue_free()
	await process_frame


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
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(200, 200)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.38, 0.4)
	mesh.material = material
	plane.mesh = mesh
	_stage.add_child(plane)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 50.0
	_stage.add_child(_camera)
