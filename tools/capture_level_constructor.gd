extends SceneTree
## Renders the planner with the right-hand map HUD and the level constructor.
## Output: /tmp/level_constructor/right_hud.png (xvfb-run godot --path . --script tools/capture_level_constructor.gd)

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const OUT := "/tmp/level_constructor/"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 20:
		await process_frame
	var entries: Node = game.get_node("LevelEntries")
	var chain: RefCounted = entries.get("chain")
	for map_name in ["lobby", "office", "lab"]:
		chain.call("add_map", map_name)
	chain.call("set_entry_type", 1, 0, "floor")
	chain.call("set_entry_type", 1, 1, "ceiling")
	chain.call("place_entry", 1, 1, 31.0, 20.0)
	entries.set("marker_map", "office")
	entries.call("refresh_markers")
	var panel: RefCounted = entries.get("_panel")
	panel.call("_refresh", 1)
	game.get("planning_mode").call("enter")
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(OUT + "right_hud.png")
	quit()
