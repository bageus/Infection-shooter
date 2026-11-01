extends SceneTree
## Level constructor: ADD MAP appends the map picked in the constructor, not the first saved map.

const MAIN := preload("res://game/bootstrap/app/main.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _run() -> void:
	root.size = Vector2i(1200, 700)
	var stage := MAIN.instantiate()
	stage.set("defer_layout_loading", true)
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var planner: Node = stage.get("planning_mode")
	planner.enter()
	await process_frame
	var storage = planner.storage
	storage.map_select.clear()
	for map_name in ["alpha", "beta", "gamma"]:
		storage.map_select.add_item(map_name)
	var entries: Node = stage.get_node("LevelEntries")
	var chain: RefCounted = entries.chain
	chain.load_dict({})
	var constructor = planner.controls.hud_layout.constructor
	var add_button := constructor.find_child("AddMap", true, false) as Button
	var picker := constructor.find_child("SavedMap", true, false) as OptionButton
	_check(add_button != null, "constructor has ADD MAP")
	_check(picker != null, "constructor has a saved map picker")
	picker.get_popup().about_to_popup.emit()
	picker.select(1)
	add_button.pressed.emit()
	_check(chain.names() == ["beta"], "ADD MAP adds the picked map, got %s" % [chain.names()])
	picker.select(2)
	add_button.pressed.emit()
	_check(chain.names() == ["beta", "gamma"], "maps are appended in order, got %s" % [chain.names()])
	picker.select(0)
	add_button.pressed.emit()
	_check(chain.names() == ["beta", "gamma", "alpha"], "third map appended, got %s" % [chain.names()])
	picker.select(1)
	add_button.pressed.emit()
	_check(chain.names() == ["beta", "gamma", "alpha"], "duplicate map is rejected, got %s" % [chain.names()])
	planner.exit()
	stage.queue_free()
	await process_frame
	print("Level constructor tests: %d failure(s)." % failures)
	quit(failures)
