extends SceneTree

const SCREEN := preload("res://game/bootstrap/app/menu/menu_screen.gd")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var menu := Control.new()
	menu.set_script(SCREEN)
	root.add_child(menu)
	menu.get("preferences").values.language = "ru"
	DirAccess.make_dir_recursive_absolute("/tmp/menu_previews")
	for kind in ["main", "pause", "failed", "complete"]:
		menu.set("screen_kind", kind)
		menu.call("refresh")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/menu_previews/" + kind + ".png")
	menu.call("activate", "settings")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/menu_previews/settings.png")
	quit()
