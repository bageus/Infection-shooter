extends SceneTree
## Renders the shared item size, the DNA pickup burst and blink, and the key objective panel.
## xvfb-run godot --path . --script res://tools/capture_item_dna_objective.gd -- /out/dir

const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const MEDKIT := preload("res://game/features/pickups/public/medkit_pickup.tscn")
const LOOT := preload("res://game/features/pickups/public/loot_drop.gd")
var _out := ""


func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.42, 0.45, 0.46)
	plane.material = floor_material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	# Drops and pickups settle on a floor collider, so the floor needs one too.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(30, 0.2, 30)
	floor_shape.position.y = -0.1
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	stage.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.07, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	stage.add_child(env)
	var impacts := Node3D.new()
	impacts.set_script(IMPACTS)
	stage.add_child(impacts)
	var player := PLAYER.instantiate() as CharacterBody3D
	player.name = "Player"
	stage.add_child(player)
	player.call("configure_world", stage, impacts)
	player.set("gravity_acceleration", 0.0)
	player.global_position = Vector3(0, 1, 0)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 2.6, 4.2)
	camera.look_at(Vector3(0, 1.1, 0))
	camera.make_current()
	var hud := HUD.instantiate()
	hud.set("player_path", NodePath("../Player"))
	stage.add_child(hud)

	# Items: a placed medkit (planner path) and a dropped one share one size.
	var placed := MEDKIT.instantiate() as Node3D
	stage.add_child(placed)
	placed.global_position = Vector3(-1.6, 0.0, 0.5)
	LOOT.spawn(stage, ["medkit"], Vector3(1.6, 0.0, 0.5), Callable())
	await _frames(40)
	_save("item_sizes.png")

	# Key in hand: the goal panel appears at the top centre.
	player.call("acquire_emergency_key")
	await _frames(60)
	_save("objective_hud.png")

	# DNA: the scale blinks and the arrow burst rises around the player.
	(player.get_node("InfectionRuntime") as Node).call("add_control_ampule")
	await _frames(9)
	_save("dna_burst_early.png")
	await _frames(20)
	_save("dna_burst_mid.png")
	quit()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(_out.path_join(name))
