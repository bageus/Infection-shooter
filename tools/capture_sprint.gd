extends SceneTree
## Contact sheet of the sprint: a row per weapon, frames along the cycle, seen from the side and from above.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_sprint.gd -- <out.png> [side|top|front|threeq]
const PLAYER := preload("res://game/features/player/public/player.tscn")
const SPRINT := preload("res://game/features/player/player_sprint.gd")
const CELL := Vector2i(360, 520)
var WEAPONS := [0, 1, 2, 3, 4, 5, 6]
var _size := 3.2
const FRAMES := 5
const VIEWS := {"top": Vector3(0.001, 1, 0.35), "side": Vector3(1, 0.2, 0), "front": Vector3(0, 0.3, -1), "threeq": Vector3(0.8, 0.5, 0.6), "left": Vector3(-1, 0.2, 0), "frontleft": Vector3(-0.8, 0.3, -0.8)}
var _out := "/tmp/sprint.png"
var _view := "side"
var _actor: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	if args.size() > 1:
		_view = args[1]
	if args.size() > 2: # e.g. "3" for the launcher only; with a fourth argument the camera size
		WEAPONS = [int(args[2])]
	if args.size() > 3:
		_size = float(args[3])
	call_deferred("_capture")


func _tick() -> void:
	SPRINT.turn_body(_actor, Vector3(0, 0, -1))
	_actor.get_node("WeaponMount").call("aim_at", _actor.global_position + Vector3(0, 1, -4))
	await process_frame


func _capture() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.84, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	stage.add_child(light)
	_actor = PLAYER.instantiate()
	stage.add_child(_actor)
	_actor.set_physics_process(false)
	_actor.call("configure_weapon_drop", func(_i: int, _p: Vector3) -> bool: return true)
	var viewport := SubViewport.new()
	viewport.size = CELL
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.world_3d = stage.get_world_3d()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _size
	viewport.add_child(camera)
	camera.current = true
	var sheet := Image.create(CELL.x * FRAMES, CELL.y * WEAPONS.size(), false, Image.FORMAT_RGBA8)
	Input.action_press("move_up")
	Input.action_press("sprint")
	var row := 0
	for index: int in WEAPONS:
		if index > 0:
			_actor.call("pickup_weapon", index)
			_actor.call("select_weapon_slot", _actor.call("get_weapon_in_slot", index) if false else _slot(index))
		_actor.get_node("AnimationDriver").call("configure_clip_selector", _actor.get("_animation_selection").select_clip)
		_actor.velocity = Vector3(0, 0, -8.1)
		for i in 14:
			await _tick()
		print("weapon ", index, " sprinting ", _actor.call("is_sprinting"), " clip ", _actor.get_node("AnimationDriver").animation_player.current_animation)
		var center := _actor.global_position + Vector3(0, 0.2 if _size > 2.0 else 0.0, 0)
		for col in FRAMES:
			for i in 3:
				await _tick()
			camera.look_at_from_position(center + VIEWS[_view] * 4.0, center, Vector3(0, 0, -1) if _view == "top" else Vector3.UP)
			await _tick()
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
		row += 1
	Input.action_release("move_up")
	Input.action_release("sprint")
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	sheet.save_png(_out)
	print("written ", _out)
	quit(0)


func _slot(weapon: int) -> int:
	for slot in 3:
		if int(_actor.call("get_weapon_in_slot", slot)) == weapon:
			return slot
	return 0
