extends SceneTree
## Contact sheet of the reload animation: one row per weapon, frames along the cycle.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_reload.gd -- <out_dir>

const PLAYER := preload("res://game/features/player/public/player.tscn")
const PHASES := [0.0, 0.2, 0.3, 0.5, 0.72, 0.9]
const WEAPONS := {0: "pistol", 4: "ak", 2: "shotgun"}
const CELL := Vector2i(300, 360)


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "/tmp/reload_review"
	DirAccess.make_dir_recursive_absolute(out)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(light)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(-2.6, 1.9, -2.0), Vector3(0, .5, .1))
	cam.current = true
	await process_frame
	var actor := PLAYER.instantiate() as CharacterBody3D
	root.add_child(actor)
	actor.set_physics_process(false)
	var effects := Node3D.new()
	root.add_child(effects)
	actor.call("configure_world", effects, null)
	actor.call("configure_weapon_drop", func(_index: int, _point: Vector3) -> bool: return true)
	await process_frame
	actor.set("_aim_point", Vector3(3, .4, 3))
	var sheet := Image.create(CELL.x * PHASES.size(), CELL.y * WEAPONS.size(), false, Image.FORMAT_RGBA8)
	var row := 0
	for index: int in WEAPONS:
		actor.call("pickup_weapon", index)
		actor.call("select_weapon_slot", index)
		print("weapon ", actor.call("get_current_weapon").call("get_weapon_name"))
		cam.current = true
		var gun: Node3D = actor.call("get_current_weapon")
		gun.set("_magazine_ammo", 0)
		gun.call("start_reload")
		var total: float = gun.get("reload_time")
		for column in PHASES.size():
			for frame in 25:
				gun.set("_reload_remaining", total * (1.0 - float(PHASES[column])))
				await process_frame
			var image := root.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(image, Rect2i(Vector2i((image.get_width() - CELL.x) / 2, (image.get_height() - CELL.y) / 2), CELL), Vector2i(column * CELL.x, row * CELL.y))
		row += 1
	sheet.save_png(out.path_join("reload_pistol_ak_shotgun.png"))
	print("Sheet written to ", out)
	quit(0)
