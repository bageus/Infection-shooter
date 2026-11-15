extends SceneTree
## Renders the hero on a flat floor with real physics: standing shot, strafing, forward walk, roll and flashlight.
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --script res://tools/capture_hero_play.gd -- <out_dir>
const PLAYER := preload("res://game/features/player/public/player.tscn")
const CELL := Vector2i(360, 360)
var _out := "/tmp/hero_play"
var _player: CharacterBody3D
var _camera: Camera3D
var _viewport: SubViewport
var _dark := false
var _aim_off := 0.0
var _offset := Vector3(2.6, 3.6, 2.6)
var _only_new := false
var _guns := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	_only_new = args.size() > 1 and args[1] == "turn_reload"
	_guns = args.size() > 1 and args[1] == "guns"
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.52, 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	stage.add_child(light)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	var mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(80, 1, 80)
	mesh.mesh = plane
	var grid := StandardMaterial3D.new()
	grid.albedo_color = Color(0.62, 0.62, 0.6)
	mesh.material_override = grid
	floor_body.add_child(mesh)
	stage.add_child(floor_body)
	_player = PLAYER.instantiate()
	stage.add_child(_player)
	_player.position = Vector3(0, 1.0, 0)
	_player.call("configure_weapon_drop", func(_i: int, _p: Vector3) -> bool: return true)
	for weapon: Node in _player.get("weapons"):
		weapon.set("effects_root", stage)
	_viewport = SubViewport.new()
	_viewport.size = CELL
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_viewport.world_3d = stage.get_world_3d()
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_viewport.add_child(_camera)
	_camera.current = true
	for i in 30:
		await _follow()
	var sheet: Array[Image] = []
	if _guns:
		await _guns_and_lean()
		quit()
		return
	if _only_new:
		await _turn_and_reload()
		quit()
		return
	_offset = Vector3(3.0, 1.5, 1.2)
	_aim_off = 0.0
	sheet.append(await _shot())
	for k in 3:
		_player.set("_aim_point", _muzzle_ahead())
		print("FIRED ", _player.call("_fire_weapon", _player.call("get_current_weapon")), " ammo ", _player.call("get_current_weapon").call("get_magazine_ammo"))
		for i in 2:
			await _follow()
		sheet.append(await _shot())
	_save(sheet, "stand_shot.png")
	_offset = Vector3(2.6, 3.6, 2.6)
	var steps := [0]
	_player.get_node("AnimationDriver").connect("footstep", func(_s: int, _v: float) -> void: steps[0] += 1)
	for action in ["move_right", "move_left", "move_up", "move_down"]:
		sheet = []
		steps[0] = 0
		Input.action_press(action)
		for i in 40:
			await _follow()
		for k in 4:
			sheet.append(await _shot())
			for i in 4:
				await _follow()
		var v := _player.velocity
		print("STEPS ", steps[0], " floor ", _player.is_on_floor(), " ")
		print("SPEED ", action, " ", Vector2(v.x, v.z).length())
		Input.action_release(action)
		_save(sheet, "walk_%s.png" % action)
		for i in 20:
			await _follow()
	for action in ["move_right", "move_left"]:
		sheet = []
		Input.action_press("sprint")
		Input.action_press(action)
		for i in 30:
			await _follow()
		for k in 6:
			sheet.append(await _shot())
			for i in 1:
				await _follow()
		print("SPRINT ", action, " ", Vector2(_player.velocity.x, _player.velocity.z).length(), " clip ", _player.get_node("AnimationDriver").animation_player.current_animation, " rate ", _player.get_node("AnimationDriver").animation_player.speed_scale)
		Input.action_release(action)
		Input.action_release("sprint")
		_save(sheet, "sprint_%s.png" % action)
		for i in 20:
			await _follow()
	sheet = []
	Input.action_press("move_right")
	for i in 10:
		await _follow()
	Input.action_press("roll")
	var start := _player.global_position
	for k in 8:
		await _follow()
		Input.action_release("roll")
		sheet.append(await _shot())
		for i in 8:
			await _follow()
	Input.action_release("move_right")
	print("ROLL travelled ", snappedf(_player.global_position.distance_to(start), 0.01), " m, body offset ", (_player.get_node("Body") as Node3D).global_position - _player.global_position)
	_save(sheet, "roll.png")
	for i in 60:
		await _follow()
	sheet = []
	sheet.append(await _shot())
	_dark = true
	_offset = Vector3(0.0, 9.0, 0.6)
	_camera.fov = 70.0
	(world.environment as Environment).ambient_light_color = Color(0.08, 0.08, 0.1)
	light.light_energy = 0.0
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_T
		key.keycode = KEY_T
		key.pressed = pressed
		Input.parse_input_event(key)
		for i in 3:
			await _follow()
	for i in 40:
		await _follow()
	var beam := _player.find_child("Flashlight", true, false) as SpotLight3D
	for i in 60:
		await _follow()
	var dark_shot := await _shot()
	var mx := 0.0
	for y in 360:
		for x in 360:
			mx = maxf(mx, dark_shot.get_pixel(x, y).get_luminance())
	print("DARKMAX ", mx, " energy ", beam.light_energy)
	sheet.append(dark_shot)
	_save(sheet, "flashlight.png")
	_offset = Vector3(2.6, 3.6, 2.6)
	_camera.fov = 40.0
	(world.environment as Environment).ambient_light_color = Color(0.7, 0.7, 0.72)
	light.light_energy = 1.0
	_player.set("health", 0.0)
	sheet = []
	print("DEATH fall seconds ", _player.call("play_death_fall"))
	for k in 6:
		sheet.append(await _shot())
		for i in 7:
			await _follow()
	_save(sheet, "death.png")
	quit()


## Turning on the spot (the cursor swings round, the feet step) and three reloads that drop the magazine differently.
func _turn_and_reload() -> void:
	var driver := _player.get_node("AnimationDriver")
	var steps := [0]
	driver.connect("footstep", func(_s: int, _v: float) -> void: steps[0] += 1)
	_offset = Vector3(2.4, 3.2, 2.4)
	var sheet: Array[Image] = []
	var size := root.size
	for side in [Vector2(0.15, 0.5), Vector2(0.85, 0.5)]:
		Input.warp_mouse(Vector2(size) * side)
		for k in 6:
			sheet.append(await _shot())
			print("TURN clip ", driver.animation_player.current_animation, " steps ", steps[0])
			for i in 5:
				await _follow()
		for i in 40:
			await _follow()
	_save(sheet, "turn_in_place.png")
	_offset = Vector3(2.2, 3.4, 2.2)
	sheet = []
	var weapon: Node = _player.call("get_current_weapon")
	var magazine := _player.get_node("Body").find_child("Magazine_Removed_Pistol", true, false) as Node3D
	_player.set("effects_root", _player.get_parent())
	# Three reloads, the hero steps aside after each: the magazines stay where they fell.
	for round in 3:
		weapon.set("_magazine_ammo", 0)
		weapon.call("start_reload")
		for frame in 200:
			await _follow()
		Input.action_press("move_right")
		for frame in 14:
			await _follow()
		Input.action_release("move_right")
		for frame in 30:
			await _follow()
		sheet.append(await _shot())
	_save(sheet, "magazine_drops.png")


## Each long gun from above with a red line along the aim from its muzzle (the drawn barrel should lie on it), then the run lean.
func _guns_and_lean() -> void:
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.012, 0.012, 5.0)
	line.mesh = box
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1, 0, 0)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = red
	root.add_child(line)
	var driver := _player.get_node("AnimationDriver")
	Input.warp_mouse(Vector2(root.size) * Vector2(0.8, 0.35))
	var sheet: Array[Image] = []
	_offset = Vector3(0.0, 2.6, 0.001)
	for slot in [4, 5, 2, 7]:
		_player.call("pickup_weapon", slot)
		for i in 150:
			await _follow()
		var muzzle := _player.call("get_current_weapon").get_node("Muzzle") as Node3D
		var forward := -(_player.get_node("AimPivot") as Node3D).global_basis.z
		line.global_position = muzzle.global_position + forward * 2.5
		line.look_at(muzzle.global_position + forward * 5.0, Vector3.UP)
		sheet.append(await _shot())
		print("GUN ", _player.call("get_current_weapon").call("get_weapon_name"), " clip ", driver.animation_player.current_animation)
	_save(sheet, "guns_aim_line.png")
	line.queue_free()
	_offset = Vector3(3.0, 1.2, 0.0)
	sheet = []
	Input.warp_mouse(Vector2(root.size) * Vector2(0.5, 0.1))
	for i in 60:
		await _follow()
	Input.action_press("move_up")
	for i in 60:
		await _follow()
	for k in 4:
		sheet.append(await _shot())
		for i in 6:
			await _follow()
	Input.action_release("move_up")
	_save(sheet, "run_lean.png")


func _muzzle_ahead() -> Vector3:
	var muzzle := _player.call("get_current_weapon").get_node("Muzzle") as Node3D
	return muzzle.global_position + (-muzzle.global_basis.z).rotated(Vector3.UP, deg_to_rad(_aim_off)) * 6.0


func _follow() -> void:
	await physics_frame
	_camera.global_position = _player.global_position + _offset
	_camera.look_at(_player.global_position + Vector3(0, 0.6, 0), Vector3.UP)


func _shot() -> Image:
	await _follow()
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


func _save(shots: Array[Image], file: String) -> void:
	var sheet := Image.create(CELL.x * shots.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		shots[i].convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, 0))
	sheet.save_png(_out + "/" + file)
