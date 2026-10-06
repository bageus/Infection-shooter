extends SceneTree

# Renders medkit/heal feedback on the player in the real mission for review.
# Output: /tmp/heal_previews/heal_sheet.png (crops around the player over time).

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const OUT := "/tmp/heal_previews/"
const CROP := Vector2i(420, 420)


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 40:
		await process_frame
	var player := game.get_node("Gameplay/Player") as Node3D
	var camera := player.get_node("CameraRig/Camera3D") as Camera3D
	player.set("camera_max_distance", 9.0)
	player.set("_camera_distance", 9.0)
	for i in 30:
		await process_frame
	player.set("health", 40.0)
	var shots: Array[Image] = []
	shots.append(await _shot(player, camera))
	player.call("heal", 35.0, &"medkit")
	for wait in [0.05, 0.15, 0.25, 0.45]:
		await create_timer(wait).timeout
		shots.append(await _shot(player, camera))
	await create_timer(1.5).timeout
	for i in 60:
		player.call("heal", 0.12)
		await process_frame
	shots.append(await _shot(player, camera))
	var sheet := Image.create(CROP.x * shots.size(), CROP.y, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CROP), Vector2i(CROP.x * i, 0))
	sheet.save_png(OUT + "heal_sheet.png")
	game.free()
	await process_frame
	quit()


func _shot(player: Node3D, camera: Camera3D) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var centre := camera.unproject_position(player.global_position + Vector3.UP * 1.2)
	var origin := Vector2i(clampi(int(centre.x) - CROP.x / 2, 0, 1280 - CROP.x), clampi(int(centre.y) - CROP.y / 2, 0, 720 - CROP.y))
	return image.get_region(Rect2i(origin, CROP))
