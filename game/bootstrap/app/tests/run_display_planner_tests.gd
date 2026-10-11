extends SceneTree
const LAYOUT_ASSERTIONS := preload("res://game/bootstrap/app/tests/layout_assertions.gd")

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const MODEL := "res://models/objects/enviroments/05/05_monitor3_server_destructible.glb"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	stage.call("_on_planning_pressed")
	var planner: Node = stage.get("planning_mode")
	var objects: Node = planner.get("objects")
	var controls: Node = planner.get("controls")
	var storage: RefCounted = planner.get("storage")
	var history: RefCounted = planner.get("edit_history")
	var prop := planner.call("_instantiate_asset", MODEL) as Node3D
	var config := {"power": "on", "content": "dynamic", "seed": 41}
	prop.call("configure_display", config)
	(planner.get("root") as Node3D).add_child(prop)
	prop.set_meta("planning_scene_path", MODEL)
	(objects.get("placed") as Array).append(prop)
	planner.call("_select", prop)
	var options: Node = controls.get("display_options")
	_check((options.get("panel") as Control).visible, "Display controls appear for selected monitor")
	(options.get("power") as OptionButton).select(1)
	options.call("_changed", 1)
	_check(prop.call("get_display_config")["power"] == "off", "UI edits power")
	history.call("undo")
	_check(prop.call("get_display_config") == config, "Undo restores full authored display config")
	history.call("duplicate_selected")
	var duplicate: Node3D = objects.get("selected")
	_check(duplicate != prop and duplicate.call("get_display_config") == config, "Duplicate preserves display choice")
	history.call("record_deleted", duplicate)
	objects.call("_delete_node", duplicate)
	await process_frame
	history.call("undo")
	var data: Dictionary = storage.call("_collect_layout_data")
	_check(data["version"] == 8, "DTO is versioned")
	var records: Array = data["objects"].filter(func(record: Dictionary) -> bool: return record["scene"] == MODEL)
	_check(records.size() == 2 and records[0]["display"] == config and records[1]["display"] == config, "Delete/undo and DTO preserve both displays")
	objects.call("_apply_layout_data", data)
	await process_frame
	var restored: Dictionary = storage.call("_collect_layout_data")
	_check(LAYOUT_ASSERTIONS.equivalent(restored, data), "Display layout round trip preserves every field")
	objects.call("_apply_layout_data", {"version": 6, "objects": [{"scene": MODEL, "x": 0, "y": 0, "z": 0}]})
	await process_frame
	var legacy: Dictionary = storage.call("_collect_layout_data")
	var defaults: Array = legacy["objects"].filter(func(record: Dictionary) -> bool: return record["scene"] == MODEL)
	_check(defaults.size() == 1 and defaults[0]["display"]["power"] == "auto", "Legacy maps receive compatible defaults")
	_check(int(defaults[0]["display"]["seed"]) > 0, "Legacy auto state receives a durable seed")
	planner.call("exit")
	stage.queue_free()
	await process_frame
	await process_frame
	print("Display planner tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
