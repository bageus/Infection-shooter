extends SceneTree
## Captures every enemy in the dark from the front, back and as a head close-up.
## usage: godot --path . -s tools/capture_enemy_glow.gd -- <output dir> [lit]
const SCENES := {
	"hunger": preload("res://game/features/infected/public/infected_hunger.tscn"),
	"brute": preload("res://game/features/infected/public/infected_brute.tscn"),
	"colossus": preload("res://game/features/infected/public/infected_colossus.tscn"),
	"horde": preload("res://game/features/infected/public/infected_horde.tscn"),
	"revenant": preload("res://game/features/infected/public/infected_revenant.tscn"),
	"titan": preload("res://game/features/infected/public/infected_titan.tscn"),
}
var output := "user://glow_review"
var lit := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	lit = args.size() > 1
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(640, 640)
	DirAccess.make_dir_recursive_absolute(output)
	for label: String in SCENES:
		await _actor(label, SCENES[label])
	quit()

func _actor(label: String, scene: PackedScene) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.02, 0.02, 0.03)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6 if lit else 0.015
	stage.add_child(environment)
	if lit:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, -30, 0)
		stage.add_child(sun)
	var actor := scene.instantiate() as CharacterBody3D
	stage.add_child(actor)
	actor.set_physics_process(false)
	var visual: Node3D = actor.body_visual
	var bounds := AABB()
	var first := true
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var center := bounds.get_center()
	var span := maxf(bounds.size.length(), 1.0)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.make_current()
	var top := Vector3(center.x, bounds.end.y - bounds.size.y * 0.12, center.z)
	for view: Array in [["front", Vector3(0.15, 0.1, -1.0), center, 0.55], ["back", Vector3(-0.15, 0.1, 1.0), center, 0.55],
			["head", Vector3(0.1, 0.0, -1.0), top, 0.38], ["shoulder", Vector3(-0.8, 0.3, 0.8), top, 0.6]]:
		camera.look_at_from_position(view[2] + (view[1] as Vector3).normalized() * span * view[3], view[2])
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%s_%s.png" % [label, view[0]]))
	stage.queue_free()
	await process_frame
