extends SceneTree
## Quests and the level chain survive save → clear → load of a named map, a saved layout and a mission start.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const LAYOUT := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const NAME := "quest_save_test"
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1200, 700)
	var stage := MAIN.instantiate()
	stage.set("defer_layout_loading", true)
	root.add_child(stage)
	await process_frame
	var planner: Node = stage.get("planning_mode")
	var storage: Variant = planner.storage
	var book: Node = stage.get("quest_book")
	var chain: RefCounted = stage.get_node("LevelEntries").chain
	var old_chain: Dictionary = chain.to_dict()
	chain.maps.clear()
	chain.add_map("alpha")
	chain.add_map("beta")
	book.add("message")
	book.add("lesson", "dna")
	book.quests[0].text = "Привет"
	storage.map_name_edit.text = NAME
	await storage.save_named_map()
	_check("заданий: 2" in planner.controls.status.text, "The save message counts the quests")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(storage._map_path(NAME)))
	_check(saved.has("quests_v1") and saved.quests_v1.size() == 2, "The map file holds the quests")
	_check(saved.has("level_chain_v1") and saved.level_chain_v1.maps.size() == 2, "The map file holds the chain structure")
	book.restore([])
	chain.maps.clear()
	await storage.load_named_map(NAME)
	_check(book.quests.size() == 2 and book.quests[0].text == "Привет", "Loading the map brings the quests back")
	_check(chain.names() == ["alpha", "beta"], "A machine without a chain adopts the map's chain")
	chain.maps.clear()
	chain.add_map("mine")
	book.restore([])
	await storage.load_named_map(NAME)
	_check(chain.names() == ["mine"], "Loading never overwrites a chain the player has")
	var read: Dictionary = storage.read_startup_layout(storage._map_path(NAME))
	book.restore([])
	var layout := LAYOUT.new(planner.get("objects"))
	var prepared: Dictionary = await layout.prepare_async(read.data, self, func(_a, _b) -> void: pass, func() -> bool: return true)
	await layout.commit_async(prepared, self, func(_a, _b) -> void: pass)
	_check(book.quests.size() == 2, "A mission start restores the quests")
	chain.load_dict(old_chain)
	DirAccess.remove_absolute(storage._map_path(NAME))
	DirAccess.remove_absolute(storage._bake_path(NAME))
	DirAccess.remove_absolute(storage._bake_path(NAME) + ".uid")
	if failures == 0:
		print("Quest save tests passed.")
	else:
		push_error("Quest save tests failed: %d failure(s)." % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
