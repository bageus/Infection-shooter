extends SceneTree
## Intact enemies from front and back, for checking seams (caps, UV, normals).
##   xvfb-run -a godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tools/capture_enemy_seams.gd -- <out dir>
const SCENES := {
	"hunger": preload("res://game/features/infected/public/infected_hunger.tscn"),
	"brute": preload("res://game/features/infected/public/infected_brute.tscn"),
	"colossus": preload("res://game/features/infected/public/infected_colossus.tscn"),
	"horde": preload("res://game/features/infected/public/infected_horde.tscn"),
	"revenant": preload("res://game/features/infected/public/infected_revenant.tscn"),
	"titan": preload("res://game/features/infected/public/infected_titan.tscn"),
}
var output := "user://seams"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(720, 720)
	DirAccess.make_dir_recursive_absolute(output)
	for label: String in SCENES:
		await _actor(label, SCENES[label])
	quit()


func _actor(label: String, scene: PackedScene) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.16, 0.18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
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
	for view: String in ["front", "back", "side"]:
		var direction: Vector3 = {"front": Vector3(0.15, 0.1, -1.0), "back": Vector3(-0.15, 0.1, 1.0), "side": Vector3(1.0, 0.1, 0.2)}[view]
		camera.look_at_from_position(center + direction.normalized() * span * 1.0, center)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%s_%s.png" % [label, view]))
	stage.queue_free()
	await process_frame
