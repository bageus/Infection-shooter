extends SceneTree
## Planner persistence: the saved map is the authored layout, not the state a
## fight left behind; the player is saved as its spawn point; missing models
## are counted; map names keep non-Latin letters; resources are found the
## export-safe way.

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const STORAGE := preload("res://game/bootstrap/app/planning_storage.gd")
const TABLE_PATH := "res://models/objects/enviroments/07/07_table.glb"
const ENEMY_PATH := "res://game/features/infected/public/infected_capsule.tscn"
const PLAYER_PATH := "res://game/features/player/public/player.tscn"

var _failures := 0


# Saving over an existing map asks for a second press; text fields keep keys.
func _test_map_overwrite(storage: Variant, planner: Node) -> void:
	var name_edit := storage.get("map_name_edit") as LineEdit
	name_edit.text = "overwrite_check"
	var path: String = storage.call("_map_path", "overwrite_check")
	DirAccess.remove_absolute(path)
	storage.call("save_named_map")
	_check(FileAccess.file_exists(path), "A new map saves on the first press")
	var _first := FileAccess.get_modified_time(path)
	storage.call("save_named_map")
	var status := str((planner.get("controls").get("status") as Label).text)
	_check(status.contains("EXISTS"), "Saving over an existing map warns first (%s)" % status)
	storage.call("save_named_map")
	_check(str((planner.get("controls").get("status") as Label).text).begins_with("MAP SAVED"), "A second press overwrites the map")
	DirAccess.remove_absolute(path)
	name_edit.grab_focus()
	_check(bool(planner.call("_text_field_has_focus")), "Typing in a planner text field keeps its keys")
	name_edit.release_focus()
	await process_frame


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(STORAGE._safe_map_name("Карта офиса 2") == "карта_офиса_2", "Russian map names stay readable")
	_check(STORAGE._safe_map_name("  ../?*  ").is_empty(), "A name without letters is rejected instead of saving '.json'")
	var stage := MAIN.instantiate()
	root.add_child(stage)
	(stage.get("player") as Node).set_physics_process(false)
	current_scene = stage
	await process_frame
	await physics_frame
	var planner: Node = stage.get("planning_mode")
	var storage: Variant = planner.get("storage")
	var objects: Variant = planner.get("objects")
	var catalog: Variant = planner.get("catalog")
	_check(not (catalog.get("group_catalogs")["07"] as Array).is_empty(), "Structure palettes are listed through ResourceLoader")

	stage.call("_on_planning_pressed")
	var player := planner.get("main_player") as Node3D
	var spawn := Vector3(3.0, 1.0, -2.0)
	objects.set("player_spawn_defined", true)
	player.global_position = spawn
	objects.set("player_spawn_transform", player.transform)
	player.set_meta("planning_scene_path", PLAYER_PATH)
	var table := _place(planner, TABLE_PATH, Vector3(6, 0, 6), false)
	var enemy := _place(planner, ENEMY_PATH, Vector3(-6, 1.0, 6), true)
	planner.call("exit")
	# The fight: the player walks off, the enemy dies, the table is shoved.
	player.global_position = Vector3(20, 1, 20)
	table.global_position += Vector3(2.5, 0, 0)
	enemy.queue_free()
	await process_frame

	stage.call("_on_planning_pressed")
	await _test_map_overwrite(storage, planner)
	var data: Dictionary = storage.call("_collect_layout_data")
	var players := (data["objects"] as Array).filter(func(r: Dictionary) -> bool: return r["scene"] == PLAYER_PATH)
	_check(players.size() == 1 and Vector3(players[0]["x"], players[0]["y"], players[0]["z"]).distance_to(spawn) < 0.01, "The player is saved once, at its spawn point")
	var enemies := (data["objects"] as Array).filter(func(r: Dictionary) -> bool: return r["scene"] == ENEMY_PATH)
	_check(enemies.size() == 1, "An enemy killed in the fight is still part of the map")
	var tables := (data["objects"] as Array).filter(func(r: Dictionary) -> bool: return r["scene"] == TABLE_PATH)
	_check(tables.size() == 1 and absf(float(tables[0]["x"]) - 6.0) < 0.05, "A shoved prop is back at its authored place")
	_check(player.global_position.distance_to(Vector3(20, 1, 20)) < 0.5, "Opening the planner does not teleport the player")

	var report: Dictionary = objects.call("_apply_layout_data", {"version": 6, "objects": [
		{"scene": TABLE_PATH, "x": 1.0, "y": 0.0, "z": 1.0},
		{"scene": "res://models/objects/enviroments/11/11_bamboo_one.glb", "x": 0.0, "y": 0.0, "z": 0.0},
		{"scene": "res://models/objects/enviroments/16/16_wall_urinal.glb", "x": 2.0, "y": 1.0, "z": 0.0},
		{"scene": "res://models/objects/enviroments/05/05_aircondition.glb", "x": 3.0, "y": 2.0, "z": 0.0},
	]})
	_check(int(report.get("skipped", -1)) == 1 and int(report.get("loaded", -1)) == 3, "Missing models are counted; the old bathroom set and retired air conditioner migrate (%s)" % report)
	planner.call("exit")
	stage.queue_free()
	await process_frame
	if _failures == 0:
		print("Planner persistence tests passed")
	quit(0 if _failures == 0 else 1)


func _place(planner: Node, path: String, at: Vector3, enemy: bool) -> Node3D:
	var node := planner.call("_instantiate_asset", path) as Node3D
	var objects: Variant = planner.get("objects")
	var session: Node = planner
	(session.get("enemies_root") if enemy else session.get("root")).add_child(node)
	node.global_position = at
	node.set_meta("planning_scene_path", path)
	if enemy:
		node.set_meta("planning_actor_kind", "enemy")
	(objects.get("placed") as Array).append(node)
	return node


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
