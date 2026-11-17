extends SceneTree
## Whole enemies as the anim viewer shows them (catalog load_body), in several clip poses, next to
## the source GLB, for checking joint tears.
##   xvfb-run -a godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tools/capture_enemy_poses.gd -- <out dir> [Name ...]
## Writes <out>/<name>_<pose>_<view>.png; pose "source" is the source GLB as authored.
const CATALOG := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_catalog.gd")
const NAMES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus"]
const POSES := [["Idle", 0.4], ["Walk", 0.3], ["AttackRight", 0.45], ["Scream", 0.5], ["Death", 0.35]]
const VIEWS := {"front": Vector3(0.25, 0.15, 1.0), "back": Vector3(-0.35, 0.25, -1.0)}
var output := "user://enemy_poses"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(640, 720)
	DirAccess.make_dir_recursive_absolute(output)
	var only := OS.get_cmdline_user_args().slice(1)
	for enemy: String in NAMES:
		if only.is_empty() or only.has(enemy):
			await _enemy(enemy)
	quit()


func _enemy(enemy: String) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.13, 0.14, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.fov = 40.0
	stage.add_child(camera)
	camera.make_current()
	var source := (load("res://models/objects/characters/enemy/%s.glb" % enemy) as PackedScene).instantiate() as Node3D
	stage.add_child(source)
	var bounds := _bounds(source)
	await _shoot(camera, bounds, Basis.IDENTITY, "%s_source" % enemy.to_lower())
	source.queue_free()
	var body := CATALOG.load_body("res://game/features/infected/public/infected_%s.tscn" % enemy.to_lower())
	stage.add_child(body)
	var player := CATALOG.find_player(body)
	bounds = _bounds(body)
	for pose: Array in POSES:
		if not player.has_animation(pose[0]):
			continue
		player.play(pose[0])
		player.seek(player.get_animation(pose[0]).length * float(pose[1]), true)
		player.pause()
		await _shoot(camera, bounds, (body.find_children("*", "MeshInstance3D", true, false)[0] as Node3D).global_transform.basis.orthonormalized(), "%s_%s" % [enemy.to_lower(), String(pose[0]).to_lower()])
	stage.queue_free()
	await process_frame


# Full body and a close-up of the shoulders and head, from the front and back of the enemy
# (`facing` turns the views with the body: the game bodies face -Z, the source GLBs +Z).
func _shoot(camera: Camera3D, bounds: AABB, facing: Basis, label: String) -> void:
	for view: String in VIEWS:
		for close in [false, true]:
			var center := bounds.get_center()
			var span := bounds.size.y * 1.55
			if close:
				center.y = bounds.position.y + bounds.size.y * 0.72
				span = bounds.size.y * 0.75
			camera.look_at_from_position(center + facing * (VIEWS[view] as Vector3).normalized() * span, center)
			await _save(label + "_" + view + ("_close" if close else ""))


func _save(label: String) -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))


static func _bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds
