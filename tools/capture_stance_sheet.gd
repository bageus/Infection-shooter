extends SceneTree
## Renders upper-body contact sheets of the player's weapon stances for visual
## review of the hands and the vest under shoulder twist.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_stance_sheet.gd -- <out_dir>
##
## Writes <out_dir>/stances.png: one row per stance (clip, time, weapon), seven
## columns: front, front-right, right side, back, back-right and right-flank
## close-ups, right-hand close-up.

const PLAYER_MODEL := preload("res://models/objects/characters/soldier_animated.glb")
const WEAPONS := {
	"pistol": "res://game/features/combat/public/pistol.tscn",
	"uzi": "res://game/features/combat/public/uzi.tscn",
	"shotgun": "res://game/features/combat/public/shotgun.tscn",
	"launcher": "res://game/features/combat/public/grenade_launcher.tscn",
}
const STANCES := [
	["Idle_Pistol_Down", 0.0, "pistol"],
	["Idle_Pistol_TwoHand", 0.0, "pistol"],
	["Walk_Pistol_TwoHand_Forward", 0.35, "uzi"],
	["Walk_Pistol_TwoHand_Right", 0.35, "uzi"],
	["Idle_Shotgun", 0.0, "shotgun"],
	["Walk_Shotgun_Left", 0.35, "shotgun"],
	["Idle_Launcher", 0.0, "launcher"],
	["Walk_Launcher_Backward", 0.35, "launcher"],
]
const CELL := Vector2i(300, 300)
# Models face +Z, so their right side is -X.
# Eye offsets from the chest (Spine2) bone.
const VIEWS := [
	Vector3(0.0, 0.3, 2.4),
	Vector3(-1.7, 0.35, 1.7),
	Vector3(-2.4, 0.3, 0.0),
	Vector3(0.0, 0.45, -2.4),
	Vector3(-0.75, 0.35, -1.0),
	Vector3(-1.15, 0.15, 0.25),
]

var _out_dir := "/tmp/stance_sheets"
var _views: Array[SubViewport] = []
var _hand_view: SubViewport


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
	for view: Vector3 in VIEWS:
		_views.append(_view(stage, Vector3.ONE, Vector3.ZERO, 40.0 if view.length() > 2.0 else 34.0))
	_hand_view = _view(stage, Vector3.ONE, Vector3.ZERO, 30.0)
	var body := PLAYER_MODEL.instantiate() as Node3D
	stage.add_child(body)
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var socket := body.find_child("WeaponSocket_R", true, false) as Node3D
	var player := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var rows: Array = []
	for stance: Array in STANCES:
		var weapon := (load(WEAPONS[stance[2]]) as PackedScene).instantiate() as Node3D
		weapon.set_script(null)
		stage.add_child(weapon)
		player.play(stance[0])
		player.seek(stance[1], true)
		player.pause()
		await process_frame
		skeleton.force_update_all_bone_transforms()
		weapon.global_transform = Transform3D(socket.global_basis.orthonormalized(), socket.global_position)
		var chest := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Spine2")).origin
		for index in VIEWS.size():
			(_views[index].get_child(0) as Camera3D).look_at_from_position(chest + VIEWS[index], chest, Vector3.UP)
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
		var camera := _hand_view.get_child(0) as Camera3D
		camera.look_at_from_position(hand + Vector3(-0.5, 0.4, 0.35), hand, Vector3.UP)
		await process_frame
		rows.append(await _shoot())
		weapon.queue_free()
	_save(rows, "stances")
	print("Stance sheet written to ", _out_dir)
	quit(0)


func _shoot() -> Array:
	await RenderingServer.frame_post_draw
	var images: Array = []
	for view in _views:
		images.append(view.get_texture().get_image())
	images.append(_hand_view.get_texture().get_image())
	return images


func _save(rows: Array, label: String) -> void:
	var columns: int = rows[0].size()
	var sheet := Image.create(CELL.x * columns, CELL.y * rows.size(), false, Image.FORMAT_RGBA8)
	for row in rows.size():
		for column in columns:
			var image: Image = rows[row][column]
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(column * CELL.x, row * CELL.y))
	sheet.save_png(_out_dir.path_join(label + ".png"))


func _view(stage: Node3D, eye: Vector3, target: Vector3, fov: float) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = CELL
	viewport.own_world_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	stage.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = fov
	viewport.add_child(camera)
	camera.look_at_from_position(eye, target, Vector3.UP)
	camera.current = true
	return viewport


func _build_stage(stage: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.32, 0.34, 0.37)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	environment.environment.ambient_light_energy = 0.6
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.3
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 150.0, 0.0)
	fill.light_energy = 0.6
	stage.add_child(fill)
