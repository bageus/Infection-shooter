extends SceneTree
## Renders the minigun held by the hero with its ammo belt, from four sides and one close-up.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_minigun_belt.gd -- <out.png>
const PLAYER := preload("res://game/features/player/public/player.tscn")
const CELL := Vector2i(640, 560)
## View direction from the hero, orthographic half-size, and look-at height.
const VIEWS := [
	[Vector3(-.8, .3, 1.0), 1.2, .45],
	[Vector3(-1, .05, 0), 1.2, .45],
	[Vector3(-.8, .25, -1.0), 1.2, .45],
	[Vector3(-.5, .3, 1.0), .6, .3],
]
var _out := "/tmp/minigun_belt.png"
var _actor: Node3D
var _viewport: SubViewport
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
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
	_viewport.add_child(_camera)
	_camera.current = true
	_actor.call("pickup_weapon", 7)
	_actor.get_node("AnimationDriver").call("configure_clip_selector", _actor.get("_animation_selection").select_clip)
	for i in 6:
		await process_frame
	var sheet := Image.create(CELL.x * VIEWS.size(), CELL.y, false, Image.FORMAT_RGBA8)
	var center := _actor.global_position + Vector3(0, 0.5, 0)
	for col in VIEWS.size():
		var view: Array = VIEWS[col]
		_camera.size = view[1]
		_camera.look_at_from_position(center + (view[0] as Vector3).normalized() * 4.0 + Vector3(0, view[2] - .5, 0), center + Vector3(0, view[2] - .5, 0))
		await process_frame
		await process_frame
		var image := _viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, 0))
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	sheet.save_png(_out)
	print("written ", _out)
	quit(0)
