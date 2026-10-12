extends SceneTree
## Renders the planner panels for crate contents, infected options and the Items tab.
## Output: /tmp/planner_loot/*.png (xvfb-run godot --path . --script tools/capture_planner_loot.gd)

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const OUT := "/tmp/planner_loot/"
const CRATE := "res://models/objects/enviroments/04/04_crate_large_broken.glb"
const HUNGER := "res://game/features/infected/public/infected_hunger.tscn"


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
	var planner: Node = game.get("planning_mode")
	planner.call("enter")
	var objects: Node = planner.get("objects")
	var controls: Node = planner.get("controls")
	var catalog: RefCounted = planner.get("catalog")
	var player: Node3D = game.get("player")
	var base := player.global_position + Vector3(0, 0, -3)
	var crate: Node3D = catalog.call("_instantiate_asset", CRATE)
	planner.get("root").add_child(crate)
	crate.global_position = base + Vector3(-1.2, 0.5, 0)
	crate.set_meta("planning_scene_path", CRATE)
	(objects.get("placed") as Array).append(crate)
	var enemy: Node3D = catalog.call("_instantiate_asset", HUNGER)
	game.get("enemies").add_child(enemy)
	enemy.global_position = base + Vector3(1.2, 1.0, 0)
	enemy.set_meta("planning_scene_path", HUNGER)
	enemy.set_meta("planning_actor_kind", "enemy")
	(objects.get("placed") as Array).append(enemy)
	var camera: Camera3D = planner.get("camera")
	camera.global_position = base + Vector3(0, 4.5, 3.5)
	camera.look_at(base, Vector3.UP)
	crate.call("configure_loot", {"mode": "manual", "items": {"medkit": 2, "ammo_pistol": 1, "antidote": 1, "weapon_6": 1}})
	enemy.call("configure_stats", {"health": 150, "damage": 75})
	enemy.call("configure_loot", {"mode": "auto"})
	objects.call("_select", crate)
	await _shot("crate_panel")
	objects.call("_select", enemy)
	await _shot("enemy_panel")
	controls.call("_show_item_catalog")
	await _shot("items_tab")
	game.free()
	await process_frame
	quit()


func _shot(name: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
