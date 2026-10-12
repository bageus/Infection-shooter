extends SceneTree
## Lit three-view contact sheet of a chair GLB.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_chair_preview.gd -- <glb path> <out.png>

const CELL := Vector2i(420, 420)
const VIEWS := [Vector3(1.3, 0.9, 1.3), Vector3(-1.3, 0.9, 1.3), Vector3(1.4, 0.5, -1.3), Vector3(0.0, 2.2, 0.8)]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_color = Color(0.5, 0.52, 0.56)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.84)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	for rot: Vector3 in [Vector3(-50, -30, 0), Vector3(-25, 150, 0)]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = rot
		sun.light_energy = 1.2
		root.add_child(sun)
	var chair := (load(args[0]) as PackedScene).instantiate() as Node3D
	root.add_child(chair)
	var aabb := AABB()
	for mesh in chair.find_children("*", "MeshInstance3D", true, false):
		aabb = aabb.merge((mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb())
	var center := aabb.get_center()
	var vps: Array[SubViewport] = []
	for view: Vector3 in VIEWS:
		var vp := SubViewport.new()
		vp.size = CELL
		vp.own_world_3d = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_4X
		root.add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 35.0
		vp.add_child(cam)
		cam.look_at_from_position(center + view * 1.1, center, Vector3.UP)
		cam.current = true
		vps.append(vp)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var sheet := Image.create(CELL.x * vps.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for i in vps.size():
		var img := vps[i].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
	sheet.save_png(args[1])
	print("vertices ", aabb)
	quit(0)
