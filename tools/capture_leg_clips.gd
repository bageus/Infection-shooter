extends SceneTree
## Renders contact sheets of the player's hips-and-legs clips (ADR-0044).
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --fixed-fps 30 --script res://tools/capture_leg_clips.gd -- <out_dir>
##
## Every sheet has a side view (top row), the game's isometric view (middle
## row) and, for runs, the old procedural gait in the same pose (bottom row).
## Sheets: run_<heading>.png for the eight headings, dodge_roll.png, dodge_strafe_forward.png,
## dodge_strafe_left.png, dodge_strafe_right.png.

const PLAYER_MODEL := preload("res://models/objects/characters/soldier_animated.glb")
const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const CLIPS := preload("res://models/objects/characters/player_legs/player_leg_clips.res")
const FRAMES := 8
const CELL := Vector2i(240, 320)
const HEADINGS := {"forward": 0.0, "forward_left": 45.0, "left": 90.0, "backward_left": 135.0, "backward": 180.0, "backward_right": -135.0, "right": -90.0, "forward_right": -45.0}

var _out_dir := "/tmp/leg_clips"
var _views: Array[SubViewport] = []


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
	_views = [_view(stage, Vector3(0.0, 1.5, 5.0), Vector3(0.0, 1.0, 0.0), 3.0), _view(stage, Vector3(6.0, 7.0, 6.0), Vector3(0.0, 0.7, 0.0), 3.4)]
	var only := OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	for heading: String in HEADINGS:
		if only.is_empty() or only == "run":
			await _run_sheet(stage, heading)
	for dodge in ["roll", "strafe_forward", "strafe_left", "strafe_right"]:
		if only.is_empty() or only == "dodge":
			await _dodge_sheet(stage, dodge)
	print("Sheets written to ", _out_dir)
	quit(0)


func _make_character(stage: Node3D, clips: bool, selector_clip: StringName) -> CharacterBody3D:
	var character := CharacterBody3D.new()
	stage.add_child(character)
	var body := PLAYER_MODEL.instantiate() as Node3D
	body.name = "Body"
	character.add_child(body)
	var driver := DRIVER.new()
	driver.name = "AnimationDriver"
	driver.procedural_gait = true
	if clips:
		driver.leg_clips = CLIPS
	driver.configure_clip_selector(func() -> StringName: return selector_clip if character.velocity.length() > 0.15 else &"Idle_Pistol_TwoHand")
	character.add_child(driver)
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var lowest := INF
	for bone in skeleton.get_bone_count():
		lowest = minf(lowest, (skeleton.global_transform * skeleton.get_bone_global_rest(bone).origin).y)
	character.position.y -= lowest - 0.03
	# Models face +Z; turn them to face +X, across the side view.
	character.rotation_degrees.y = 90.0
	return character


func _run_sheet(stage: Node3D, heading: String) -> void:
	var rows: Array = []
	var speed := 5.0
	for clips in [true, false]:
		var character := _make_character(stage, clips, &"Walk_Pistol_TwoHand_Forward")
		var angle := deg_to_rad(float(HEADINGS[heading]))
		character.velocity = character.global_basis * (Vector3(sin(angle), 0.0, cos(angle)) * speed)
		for i in 40:
			await process_frame
		var images: Array = []
		for frame in FRAMES:
			for i in 2:
				await process_frame
			images.append(await _shoot())
		rows.append(images)
		character.queue_free()
		await process_frame
	_save(rows, "run_" + heading)


func _dodge_sheet(stage: Node3D, kind: String) -> void:
	var character := _make_character(stage, true, &"Walk_Pistol_TwoHand_Forward")
	var driver := character.get_node("AnimationDriver")
	driver.dodge_style = 0 if kind == "roll" else 1
	var heading := deg_to_rad({"roll": 0.0, "strafe_forward": 0.0, "strafe_left": 90.0, "strafe_right": -90.0}[kind])
	var direction: Vector3 = character.global_basis * Vector3(sin(heading), 0.0, cos(heading))
	var duration := 0.55
	character.velocity = direction * 5.0
	for i in 30:
		await process_frame
	driver.play_dodge(direction, duration)
	var images: Array = []
	var start := Time.get_ticks_msec()
	for frame in FRAMES + 1:
		# Sample evenly over the dodge; --fixed-fps 30 advances 1/30 s per frame.
		var wait := int(round(duration * 30.0 / float(FRAMES)))
		for i in wait:
			await process_frame
		images.append(await _shoot())
	_save([images], "dodge_" + kind)
	character.queue_free()
	await process_frame


func _shoot() -> Array:
	await RenderingServer.frame_post_draw
	var images: Array = []
	for view in _views:
		images.append(view.get_texture().get_image())
	return images


# rows: [[ [side, iso] per frame ], ...]; each row contributes a side and an iso strip.
func _save(rows: Array, label: String) -> void:
	var frame_count: int = rows[0].size()
	var sheet := Image.create(CELL.x * frame_count, CELL.y * 2 * rows.size(), false, Image.FORMAT_RGBA8)
	for row in rows.size():
		for frame in frame_count:
			for view in 2:
				var image: Image = rows[row][frame][view]
				image.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(frame * CELL.x, (row * 2 + view) * CELL.y))
	sheet.save_png(_out_dir.path_join(label + ".png"))


func _view(stage: Node3D, eye: Vector3, target: Vector3, size: float) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = CELL
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.world_3d = stage.get_world_3d()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size
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
