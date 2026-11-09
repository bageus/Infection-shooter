extends SceneTree
## Renders the player idle legs (pistol, shotgun, launcher) from four sides, zoomed on the lower body.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_weapon_hold.gd -- <out.png> [no_stance]
##
## Writes one sheet: a row per weapon, columns front, back, left, right.
const PLAYER := preload("res://game/features/player/public/player.tscn")
const CELL := Vector2i(480, 400)
const NAMES := ["pistol", "uzi", "shotgun", "grenade", "ak", "m4", "sniper", "minigun"]
const ROWS := [0, 2, 3, -1]  # -1: lowered pistol idle
const VIEWS := {"front": Vector3(0, 0, 1), "back": Vector3(0, 0, -1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0)}
var _no_stance := false
var _out := "/tmp/weapon_hold.png"
var _actor: Node3D
var _viewport: SubViewport
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	_no_stance = args.has("no_stance")
	call_deferred("_capture")


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
	_actor.set("_aim_point", Vector3.INF)
	_viewport = SubViewport.new()
	_viewport.size = CELL
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_viewport.world_3d = stage.get_world_3d()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.5
	_viewport.add_child(_camera)
	_camera.current = true
	var sheet := Image.create(CELL.x * 4, CELL.y * ROWS.size(), false, Image.FORMAT_RGBA8)
	for row in ROWS.size():
		var index: int = ROWS[row]
		if index > 0:
			_actor.call("pickup_weapon", index)
		if index < 0:
			_actor.get_node("AnimationDriver").call("configure_clip_selector", func() -> StringName: return &"Idle_Pistol_Down")
		else:
			_actor.get_node("AnimationDriver").call("configure_clip_selector", _actor.get("_animation_selection").select_clip)
		for i in 4:
			await process_frame
		if _no_stance:
			for feet in _actor.find_children("StanceFeet", "", true, false):
				feet.queue_free()
			await process_frame
		var col := 0
		var center := _actor.global_position + Vector3(0, -0.15, 0)
		for view: String in ["front", "back", "left", "right"]:
			_camera.look_at_from_position(center + VIEWS[view] * 4.0, center)
			await process_frame
			await RenderingServer.frame_post_draw
			var image := _viewport.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
			col += 1
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	sheet.save_png(_out)
	print("written ", _out)
	quit(0)
