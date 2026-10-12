extends SceneTree
## Lit multi-angle renders of the player holding AK / M4 / sniper rifle / minigun
## to review how the long guns sit against the body.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_long_gun_grip.gd -- <out_dir>

const PLAYER := preload("res://game/features/player/public/player.tscn")
const CELL := Vector2i(360, 360)
const VIEWS := [
	Vector3(2.2, 1.2, 0.0),   # model-right side
	Vector3(-2.2, 1.2, 0.0),  # model-left side
	Vector3(0.0, 1.2, 2.2),   # front
	Vector3(0.0, 1.2, -2.2),  # back
	Vector3(1.4, 2.6, 0.8),   # above
	Vector3(1.0, 1.1, 1.2),   # front-right close
]
var _out := "/tmp/long_gun_grip"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.34, 0.37)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.82)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	for rot: Vector3 in [Vector3(-50, -30, 0), Vector3(-25, 150, 0)]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = rot
		sun.light_energy = 1.1
		root.add_child(sun)
	var actor := PLAYER.instantiate() as Node3D
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.call("configure_world", Node3D.new(), null)
	actor.call("configure_weapon_drop", func(_index: int, _point: Vector3) -> bool: return true)
	actor.set("_aim_point", Vector3(0, .4, -30))
	var cams: Array[SubViewport] = []
	for view in VIEWS:
		var vp := SubViewport.new()
		vp.size = CELL
		vp.own_world_3d = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_4X
		root.add_child(vp)
		var cam := Camera3D.new()
		cam.fov = 38.0
		vp.add_child(cam)
		cam.current = true
		cams.append(vp)
	var rows: Array = []
	var labels := {4: "ak", 5: "m4", 6: "sniper", 7: "minigun"}
	for index in [4, 5, 6, 7]:
		actor.call("pickup_weapon", index)
		actor.set("_aim_point", Vector3(0, .4, -30))
		for i in 2:
			await process_frame
		var skel := actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var center: Vector3 = skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Spine2")).origin
		for i in VIEWS.size():
			((cams[i]).get_child(0) as Camera3D).look_at_from_position(center + VIEWS[i] * 0.75 - Vector3(0, 0.9, 0), center, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		var row: Array = []
		for vp in cams:
			row.append(vp.get_texture().get_image())
		rows.append(row)
		print("captured ", labels[index], " hand_error ", actor.get_node("WeaponMount").get("equipment_pose").hand_error)
	var sheet := Image.create(CELL.x * VIEWS.size(), CELL.y * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in VIEWS.size():
			var img: Image = rows[r][c]
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, r * CELL.y))
	sheet.save_png(_out.path_join("long_guns.png"))
	quit(0)
