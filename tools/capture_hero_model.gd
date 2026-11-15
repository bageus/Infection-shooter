extends SceneTree
## Renders the player scene with the baked soldier model: weapon grips, a walk cycle and a reload per weapon.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_hero_model.gd -- <out_dir>
##
## Writes <out_dir>/grips.png, walk.png and reload.png.
const PLAYER := preload("res://game/features/player/public/player.tscn")
const CELL := Vector2i(360, 420)
const NAMES := ["pistol", "uzi", "shotgun", "launcher", "ak", "m4", "sniper", "minigun"]
const WALK_WEAPONS := [0, 3, 4]
const RELOAD_WEAPONS := [0, 2, 4, 6]
const RELOAD_SHOTS := [0.12, 0.3, 0.5, 0.8]
var _out := "/tmp/hero_model"
var _actor: Node3D
var _camera: Camera3D
var _viewport: SubViewport


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
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
	for index in range(1, 8):
		_actor.call("pickup_weapon", index)
	_viewport = SubViewport.new()
	_viewport.size = CELL
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_viewport.world_3d = stage.get_world_3d()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.6
	_viewport.add_child(_camera)
	_camera.current = true
	# Three-quarter view from the weapon side; the body faces the camera's far side (-Z in the actor's frame).
	_camera.look_at_from_position(Vector3(2.0, 1.2, -2.2), Vector3(0, 0.95, 0), Vector3.UP)
	await _sheet("grips.png", await _grips())
	await _sheet("walk.png", await _walks())
	await _sheet("reload.png", await _reloads())
	_camera.look_at_from_position(Vector3(-0.8, 1.3, 2.6), Vector3(0, 0.95, 0), Vector3.UP)
	await _sheet("backpack.png", await _backpack())
	quit()


func _face_aim() -> void:
	var point := _actor.global_position + Vector3(0, 1.0, -5.0)
	_actor.set("_aim_point", point)
	_actor.get_node("AimPivot").look_at(point, Vector3.UP)
	_actor.get_node("Body").global_rotation = Vector3(0.0, atan2(0.0, -1.0), 0.0)
	_actor.get_node("WeaponMount").call("aim_at", point)


func _select(index: int) -> void:
	_actor.set("current_weapon_index", 0)
	_actor.get("weapon_stance").call("select_weapon", index)
	for i in 8:
		(_actor.get("weapons") as Array)[i].visible = i == index
	_actor.get_node("WeaponMount").call("select_weapon", (_actor.get("weapons") as Array)[index])
	_actor.get_node("AnimationDriver").call("configure_clip_selector", _actor.get("_animation_selection").select_clip)


func _shot() -> Image:
	await process_frame
	await process_frame
	return _viewport.get_texture().get_image()


func _grips() -> Array[Image]:
	var shots: Array[Image] = []
	for index in 8:
		_select(index)
		_actor.velocity = Vector3.ZERO
		for i in 4:
			_face_aim()
			await process_frame
		shots.append(await _shot())
	return shots


func _walks() -> Array[Image]:
	var shots: Array[Image] = []
	for index in WALK_WEAPONS:
		_select(index)
		_actor.velocity = Vector3(0, 0, -2.5)
		for frame in 4:
			for i in 8:
				_face_aim()
				await process_frame
			shots.append(await _shot())
	_actor.velocity = Vector3.ZERO
	return shots


## The backpack from behind: standing, then four moments of a run (its own bone swings in the baked clips).
func _backpack() -> Array[Image]:
	var shots: Array[Image] = []
	_select(4)
	_actor.velocity = Vector3.ZERO
	for i in 6:
		_face_aim()
		await process_frame
	shots.append(await _shot())
	_actor.velocity = Vector3(0, 0, -7.5)
	for frame in 3:
		for i in 6:
			_face_aim()
			await process_frame
		shots.append(await _shot())
	_actor.velocity = Vector3.ZERO
	return shots


func _reloads() -> Array[Image]:
	var shots: Array[Image] = []
	for index in RELOAD_WEAPONS:
		_select(index)
		_actor.velocity = Vector3.ZERO
		var weapon: Node3D = (_actor.get("weapons") as Array)[index]
		weapon.set("_magazine_ammo", 0 if index != 2 else 1)
		weapon.call("start_reload")
		var total := float(weapon.get("reload_time"))
		var elapsed := 0.0
		for fraction: float in RELOAD_SHOTS:
			while elapsed < total * fraction:
				_face_aim()
				await process_frame
				elapsed += 1.0 / 60.0
			shots.append(await _shot())
		weapon.call("cancel_reload")
	return shots


func _sheet(file: String, shots: Array[Image]) -> void:
	var columns := 4
	var rows := ceili(shots.size() / float(columns))
	var sheet := Image.create(CELL.x * columns, CELL.y * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		shots[i].convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i((i % columns) * CELL.x, (i / columns) * CELL.y))
	sheet.save_png("%s/%s" % [_out, file])
	print("wrote ", file)
