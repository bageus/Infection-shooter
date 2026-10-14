extends SceneTree
## Plays the Hunger's new states in the real enemy scene and writes frames for
## review (ADR-0045). A separate script (tools/make_hunger_gif.py) joins them.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --fixed-fps 30 --script res://tools/capture_hunger_states.gd -- <out_dir>
##
## Scenarios: rest (idle scream, turn on the spot, groan), aggro (scream, stalk,
## all-fours sprint, stand up, swing), crawl (leg shot off, crawl, claw), feed
## (gnaws a corpse, then jumps up), flinch (hit while running).

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const SIZE := Vector2i(480, 360)
const EVERY := 2

var _out_dir := "/tmp/hunger_states"
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
	for scenario: String in ["rest", "aggro", "crawl", "feed", "flinch"]:
		await _play(scenario)
	print("Frames written to ", _out_dir)
	quit(0)


func _play(scenario: String) -> void:
	_build_stage()
	var target := FakeTarget.new()
	_stage.add_child(target)
	target.position = Vector3(0, 0.1, -14.0)
	var hunter := HUNGER.instantiate() as CharacterBody3D
	_stage.add_child(hunter)
	hunter.position = Vector3(0, 0.1, 0)
	_subject = hunter
	var frames := 300
	var events := {}
	match scenario:
		"rest":
			target.position = Vector3(0, 0.1, -60.0)
			hunter.call("watch_target", target)
			hunter.get("_senses").wander_enabled = false
			events = {10: func() -> void: hunter.call("_idle_flavor", true), 90: func() -> void: _face(hunter, Vector3(1, 0, 0.4)), 220: func() -> void: hunter.call("_idle_flavor", false)}
			frames = 420
		"aggro":
			target.position = Vector3(0, 0.1, -16.0)
			hunter.set("_feral", true)
			hunter.call("watch_target", target)
			hunter.global_position = Vector3(0, 0.1, 0)
			hunter.get("_senses").sight_range = 30.0
			frames = 420
		"crawl":
			target.position = Vector3(0, 0.1, -7.0)
			hunter.call("set_target", target)
			events = {20: func() -> void: hunter.get("_parts").sever(&"leg_r", Vector3.RIGHT)}
			frames = 420
		"feed":
			var victim := HUNGER.instantiate() as CharacterBody3D
			_stage.add_child(victim)
			victim.position = Vector3(1.6, 0.1, 0)
			target.position = Vector3(0, 0.1, -60.0)
			hunter.call("watch_target", target)
			hunter.get("_senses").wander_enabled = false
			events = {
				5: func() -> void: victim.call("take_damage", 9999.0),
				20: func() -> void: _start_feeding(hunter, victim),
				150: func() -> void: hunter.call("hear_alert", hunter.global_position, 40.0),
			}
			frames = 240
		"flinch":
			target.position = Vector3(0, 0.1, -12.0)
			hunter.call("set_target", target)
			events = {50: func() -> void: hunter.call("take_projectile_damage", 16.0, hunter.global_position + Vector3(0.2, 1.4, 0.1), Vector3(-0.3, 0, -1).normalized(), "PISTOL")}
			frames = 150
	await process_frame
	for frame in frames:
		if events.has(frame):
			(events[frame] as Callable).call()
		await physics_frame
		if frame < 6 or frame % 30 == 0 and OS.get_environment("HUNGER_DEBUG") != "":
			var ap := hunter.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
			print(scenario, " ", frame, " anim=", ap.current_animation, " pos=", ap.current_animation_position, " busy=", hunter.get("_busy"), " feeding=", hunter.get("_feeding"), " active=", ap.active, " chasing=", hunter.call("is_alerted"), " drv=", hunter.get_node("AnimationDriver").is_processing())
		if frame % EVERY == 0:
			_aim_camera()
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/%s_%03d.png" % [_out_dir, scenario, frame / EVERY])
	_stage.queue_free()
	await process_frame


func _face(hunter: Node, direction: Vector3) -> void:
	hunter.set("_face_direction", direction.normalized())
	hunter.call("_start_turn_if_needed", hunter.rotation.y)


func _start_feeding(hunter: Node, victim: Node3D) -> void:
	hunter.set("_corpse", victim)
	hunter.get("_senses").state = 2
	hunter.call("_rest_behaviour", 0.016)
	print("feed start: feeding=", hunter.call("is_feeding"), " corpse=", victim.global_position, " hunter=", hunter.global_position)


func _aim_camera() -> void:
	var at := _subject.global_position + Vector3(0, 0.9, 0)
	_camera.look_at_from_position(at + Vector3(2.6, 1.5, 3.1), at)


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
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(120, 120)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.38, 0.4)
	mesh.material = material
	plane.mesh = mesh
	_stage.add_child(plane)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 50.0
	_stage.add_child(_camera)
