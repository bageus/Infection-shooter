extends SceneTree
## A manual enemy drop can carry the key; auto loot never rolls it.
const LOOT_DROP := preload("res://game/features/pickups/public/loot_drop.gd")
const CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const DROP_TABLE := preload("res://game/features/pickups/public/drop_table.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var config := CONFIG.sanitize({"mode": "manual", "items": {"key": 1}})
	_check(config["items"].get("key", 0) == 1, "Key survives sanitize in a manual config.")
	_check(CONFIG.manual_list(config).has("key"), "Manual list includes the key.")
	_check(not CONFIG.AUTO_WEIGHTS.has("key"), "Auto loot never rolls the key.")
	LOOT_DROP.release_enemy(stage, Vector3(0, 0, 0), config, Callable())
	await process_frame
	var keys := 0
	for node in get_nodes_in_group("mission_key"):
		keys += 1
	_check(keys == 1, "Manual enemy drop spawns exactly one key.")
	for node in get_nodes_in_group(DROP_TABLE.DROP_GROUP):
		_check(node.has_meta(&"persistent_loot"), "Key drop stays until collected.")
	stage.queue_free()
	print("Key drop tests: %d failures" % failures)
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + message)
