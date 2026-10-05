extends SceneTree

const SCREEN := preload("res://game/bootstrap/app/menu/menu_screen.gd")
const MAIN := preload("res://game/bootstrap/app/main.tscn")


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
	for language in ["ru", "en"]:
		menu.preferences.values.language = language
		menu.preferences.values.text_scale = 1.3
		menu.call("activate", "settings")
		for tab in 4:
			menu.modal.settings.tabs.current_tab = tab
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/menu_previews/settings_%s_%d.png" % [language, tab])
		menu.call("close_dialog")
	menu.preferences.values.language = "ru"
	menu.call("activate", "about")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/menu_previews/vectrion_history.png")
	menu.call("close_dialog")
	menu.set("screen_kind", "main")
	menu.get("preferences").values.text_scale = 1.3
	menu.call("refresh")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/menu_previews/main_130.png")
	menu.free()
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/menu_previews/gameplay.png")
	game.get("planning_mode").call("enter")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/menu_previews/planner.png")
	quit()
