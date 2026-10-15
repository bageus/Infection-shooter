extends SceneTree
## Identical deterministic fixture for the base and candidate revisions.
const SCENES := {
	"hunger": preload("res://game/features/infected/public/infected_hunger.tscn"),
	"brute": preload("res://game/features/infected/public/infected_brute.tscn"),
	"colossus": preload("res://game/features/infected/public/infected_colossus.tscn"),
	"horde": preload("res://game/features/infected/public/infected_horde.tscn"),
	"revenant": preload("res://game/features/infected/public/infected_revenant.tscn"),
	"titan": preload("res://game/features/infected/public/infected_titan.tscn"),
	"mutant_level2": preload("res://game/features/infected/public/mutant_level2.tscn"),
}
const RAGDOLL := preload("res://game/features/infected/death_ragdoll.gd")
var output := "user://skin_review"

func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
	call_deferred("_run")

func _run() -> void:
	seed(20261015)
	root.size = Vector2i(640, 640)
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
	visual.process_mode = Node.PROCESS_MODE_DISABLED
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
	camera.look_at_from_position(center + Vector3(0.15, 0.1, -1.0).normalized() * span * 1.15, center)
	camera.make_current()
	await _save(label + "_clean")
	var parts: Node = actor._parts
	for entry: Dictionary in parts._entries:
		var surface: Dictionary = entry.data.surfaces[0]
		var points: PackedVector3Array = surface.vertices
		for index in [0, points.size() / 3, points.size() * 2 / 3]:
			parts.add_rest_wound(points[index], 0.12)
	await _save(label + "_wounded")
	parts.sever(&"arm_l" if parts.parts.has(&"arm_l") else &"tentacle_0", Vector3.ZERO)
	for child in stage.get_children():
		if child is RigidBody3D:
			child.freeze = true
	await _save(label + "_severed")
	# Real death wiring, with deterministic clip fallback rather than random ragdoll.
	RAGDOLL._active = RAGDOLL.MAX_ACTIVE
	visual.process_mode = Node.PROCESS_MODE_INHERIT
	actor.health = 0.0
	actor.call("_die")
	RAGDOLL._active = 0
	actor.set_physics_process(false)
	await create_timer(1.8).timeout
	await _save(label + "_corpse")
	stage.queue_free()
	await process_frame

func _save(label: String) -> void:
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty())
	assert(image.save_png(output.path_join(label + ".png")) == OK)
