extends SceneTree
## Renders walking player frames (side view, several moments of the stride) per weapon.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_walk_pose.gd -- <out.png> [left|right|front|back|threeq|threeq_l]
##
## Writes one sheet: a row per weapon, columns front, back, left, right.
const PLAYER := preload("res://game/features/player/public/player.tscn")
const CELL := Vector2i(480, 800)
const NAMES := ["pistol", "uzi", "shotgun", "grenade", "ak", "m4", "sniper", "minigun"]
const SHOW := [0]
const FRAMES := 4
const VIEWS := {"threeq": Vector3(.7, 0, .7), "threeq_l": Vector3(-.7, 0, .7), "front": Vector3(0, 0, 1), "back": Vector3(0, 0, -1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0)}
var _out := "/tmp/walk_pose.png"
var _view := "left"
var _actor: Node3D
var _viewport: SubViewport
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	if args.size() > 1:
		_view = args[1]
	call_deferred("_capture")


## Mimics gameplay: the cursor point turns the aim pivot and body, then the mount aims the torso.
func _tick() -> void:
	var point := _actor.global_position + Vector3(1.5, 1.2, -4.0)
	var flat := point - _actor.global_position
	flat.y = 0.0
	_actor.set("_aim_point", point)
	_actor.get_node("AimPivot").look_at(_actor.get_node("AimPivot").global_position + flat.normalized(), Vector3.UP)
	preload("res://game/features/player/player_body_aim.gd").turn_body(_actor.get_node("Body"), flat.normalized(), 1.0 / 60.0)
	_actor.get_node("WeaponMount").call("aim_at", point)
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
	_actor.get_node("Body").rotation = Vector3.ZERO
	_actor.get_node("AimPivot").rotation.y = 0.0
	_actor.call("configure_weapon_drop", func(_i: int, _p: Vector3) -> bool: return true)
	_viewport = SubViewport.new()
	_viewport.size = CELL
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_viewport.world_3d = stage.get_world_3d()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.2
	_viewport.add_child(_camera)
	_camera.current = true
	var sheet := Image.create(CELL.x * FRAMES, CELL.y * SHOW.size(), false, Image.FORMAT_RGBA8)
	var row := 0
	for index in SHOW:
		if index > 0:
			_actor.call("pickup_weapon", index)
		_actor.get_node("AnimationDriver").call("configure_clip_selector", _actor.get("_animation_selection").select_clip)
		# AimPivot faces -Z; walking forward is local -Z.
		_actor.velocity = Vector3(0, 0, -2.5)
		for i in 10:
			await _tick()
		var center := _actor.global_position + Vector3(0, 0.7, 0)
		for col in FRAMES:
			for i in 7:
				await _tick()
			_camera.look_at_from_position(center + VIEWS[_view] * 4.0, center)
			await _tick()
			await RenderingServer.frame_post_draw
			var image := _viewport.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
		row += 1
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	sheet.save_png(_out)
	print("written ", _out)
	quit(0)
