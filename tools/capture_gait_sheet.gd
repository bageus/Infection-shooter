extends SceneTree
## Renders locomotion contact sheets for visual review of walk/run cycles.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --fixed-fps 30 --script res://tools/capture_gait_sheet.gd -- <out_dir>
##
## Writes <out_dir>/<subject>.png: side view on the top row and front view on
## the bottom row, eight evenly spaced frames of one cycle. Enemy rows sample
## the baked clips; the player row runs the procedural gait at walk speed.

const PLAYER_MODEL := preload("res://models/objects/characters/soldier_animated.glb")
const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const ENEMY_DIR := "res://models/objects/characters/enemy/game/"
const ENEMIES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus"]
const FRAMES := 8
const CELL := Vector2i(260, 340)

var _out_dir := "/tmp/gait_sheets"
var _side: SubViewport
var _front: SubViewport


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := Node3D.new()
	root.add_child(stage)
	_build_stage(stage)
	_side = _view(stage, Vector3(0.0, 1.9, 5.0), Vector3(0.0, 1.15, 0.0))
	_front = _view(stage, Vector3(5.0, 1.9, 0.0), Vector3(0.0, 1.15, 0.0))
	await _capture_player(stage, 6.0, "player_walk")
	await _capture_player(stage, 9.0, "player_sprint")
	for enemy: String in ENEMIES:
		for clip in ["Walk", "Run"]:
			await _capture_enemy(stage, enemy, clip)
	print("Gait sheets written to ", _out_dir)
	quit(0)


func _capture_player(stage: Node3D, speed: float, label: String) -> void:
	var character := CharacterBody3D.new()
	stage.add_child(character)
	var body := PLAYER_MODEL.instantiate() as Node3D
	body.name = "Body"
	character.add_child(body)
	var driver := DRIVER.new()
	driver.name = "AnimationDriver"
	driver.procedural_gait = true
	driver.configure_clip_selector(func() -> StringName: return &"Walk_Pistol_TwoHand_Forward")
	character.add_child(driver)
	_stand_on_floor(character, body)
	# Models face +Z; turn them to walk along +X, across the side view.
	character.rotation_degrees.y = 90.0
	character.velocity = character.global_basis * Vector3(0.0, 0.0, speed)
	for i in 45:
		await process_frame
	var gait: Object = driver.gait
	var cadence := minf(float(gait.get("max_cadence")), float(gait.get("base_cadence")) + float(gait.get("cadence_per_mps")) * speed)
	var step := maxi(1, roundi(30.0 / cadence / FRAMES))
	var images: Array = []
	for frame in FRAMES:
		for i in step:
			await process_frame
		images.append(await _shoot())
	_save(images, label)
	character.queue_free()
	await process_frame


func _capture_enemy(stage: Node3D, enemy: String, clip: String) -> void:
	var rig := (load(ENEMY_DIR + enemy + "_rig.tscn") as PackedScene).instantiate() as Node3D
	stage.add_child(rig)
	rig.rotation_degrees.y = 90.0
	# Body scales of the enemy scenes (tools/build_enemy_rigs.gd STYLES).
	var style_scale := {"Titan": 1.35, "Colossus": 1.55, "Brute": 1.1}
	rig.scale = Vector3.ONE * float(style_scale.get(enemy, 1.0))
	_stand_on_floor(rig, rig)
	var player := rig.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.play(clip)
	player.pause()
	var length := player.get_animation(clip).length
	var images: Array = []
	for frame in FRAMES:
		player.seek(length * float(frame) / FRAMES, true)
		await process_frame
		images.append(await _shoot())
	_save(images, enemy.to_lower() + "_" + clip.to_lower())
	rig.queue_free()
	await process_frame


# Lifts the subject so its lowest rest-pose bone sits on the floor.
func _stand_on_floor(subject: Node3D, model: Node) -> void:
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var lowest := INF
	for bone in skeleton.get_bone_count():
		var point := skeleton.global_transform * skeleton.get_bone_global_rest(bone).origin
		lowest = minf(lowest, point.y)
	subject.position.y -= lowest - 0.03


func _shoot() -> Array:
	await RenderingServer.frame_post_draw
	return [_side.get_texture().get_image(), _front.get_texture().get_image()]


func _save(images: Array, label: String) -> void:
	var sheet := Image.create(CELL.x * FRAMES, CELL.y * 2, false, Image.FORMAT_RGBA8)
	for frame in images.size():
		for row in 2:
			var image: Image = images[frame][row]
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(frame * CELL.x, row * CELL.y))
	sheet.save_png(_out_dir.path_join(label + ".png"))


func _view(stage: Node3D, eye: Vector3, target: Vector3) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = CELL
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.world_3d = stage.get_world_3d()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	viewport.add_child(camera)
	camera.look_at_from_position(eye, target)
	camera.current = true
	return viewport


func _build_stage(stage: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.82, 0.84, 0.86)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.47, 0.5)
	plane.material = material
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	# Midline marker: feet of a natural gait land close to it.
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.0, 0.004, 0.02)
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.9, 0.3, 0.2)
	box.material = line_material
	line.mesh = box
	stage.add_child(line)
