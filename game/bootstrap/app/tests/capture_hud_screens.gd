extends SceneTree

# Renders the combat HUD over the real mission at 1280x720 for visual review:
# a fresh start, and a later state with the emergency key, mutation and an
# empty magazine. Output: /tmp/hud_previews/*.png

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const OUT := "/tmp/hud_previews/"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "hud_start.png")
	var player := game.get_node("Gameplay/Player")
	player.call("acquire_emergency_key")
	player.call("absorb_mutagen", 4.0)
	player.set("health", player.get("max_health") * 0.42)
	var weapon: Node = player.call("get_current_weapon")
	weapon.set("_magazine_ammo", 0)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "hud_key.png")
	game.free()
	await process_frame
	quit()
