extends SceneTree
## Side contact sheet of a killed infected falling onto a ledge, to check that the legs settle.
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --script res://tools/capture_death_settle.gd -- <out.png> [ledge|floor] [SHOTGUN|PISTOL]
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const CELL := Vector2i(300, 260)
const TIMES := [0.0, 1.0, 1.6, 4.0, 6.0, 9.0]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	preload("res://game/features/infected/public/corpse_budget.gd").keep = true
	var args := OS.get_cmdline_user_args()
	var ledge := args.size() < 2 or args[1] == "ledge"
	var weapon := args[2] if args.size() > 2 else "SHOTGUN"
	var stage := Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.82, 0.84, 0.86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.82)
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	stage.add_child(light)
	_box(stage, Vector3(0, -0.5, 0), Vector3(40, 1, 40), 3, Color(0.45, 0.47, 0.5))
	if ledge:
		_box(stage, Vector3(0, 0.35, -1.3), Vector3(0.8, 0.7, 4), 1, Color(0.6, 0.45, 0.3))
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = Vector3(1.6, 0.96, 0)
	enemy.rotation.y = 0.0
	await create_timer(0.5).timeout
	enemy.rotation.y = -PI / 2.0 # faces +z... model front is -z basis; turn so the fall runs along -x
	var view := SubViewport.new()
	view.size = CELL
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.world_3d = stage.get_world_3d()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.6
	view.add_child(cam)
	cam.look_at_from_position(Vector3(0.4, 0.6, 6), Vector3(0.4, 0.6, 0))
	cam.current = true
	var sheet := Image.create(CELL.x * TIMES.size(), CELL.y, false, Image.FORMAT_RGBA8)
	enemy.velocity = Vector3(0, 0, 0)
	var dir := Vector3(-1, 0, 0)
	enemy.call("take_projectile_damage", 1000.0, enemy.global_position + Vector3.UP * 0.2, dir, weapon)
	var t := 0.0
	for i in TIMES.size():
		await create_timer(TIMES[i] - t).timeout if TIMES[i] > t else await process_frame
		t = TIMES[i]
		var x := enemy.global_position.x
		cam.look_at_from_position(Vector3(x, 0.6, 6), Vector3(x, 0.6, 0))
		await process_frame
		await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
	sheet.save_png(args[0])
	quit(0)

func _box(stage: Node3D, at: Vector3, size: Vector3, layer: int, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	bm.material = m
	mesh.mesh = bm
	body.add_child(mesh)
	stage.add_child(body)
	body.position = at
