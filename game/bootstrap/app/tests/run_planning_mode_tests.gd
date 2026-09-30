extends SceneTree

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const LIGHT_PATH := "res://game/presentation/office_floor/public/props/planner_light.tscn"
const TABLE_PATH := "res://models/objects/enviroments/07/07_table.glb"
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	await physics_frame
	var planner: Node = stage.get("planning_mode")
	stage.call("_on_planning_pressed")
	_check(planner.get("active") and paused, "Planning opens and pauses gameplay")
	_check(not (stage.get_node("PrototypeHUD") as CanvasLayer).visible, "Planning hides HUD")
	var camera := planner.get("camera") as Camera3D
	var before := camera.global_position
	planner.call("_zoom_camera", 2.5)
	_check(camera.global_position.y > before.y, "Planning camera responds to wheel command")
	await _exercise_edits(planner)
	await _exercise_maps(planner)
	planner.call("exit")
	_check(not paused and not planner.get("active"), "Planning exits and resumes gameplay")
	_check((stage.get_node("PrototypeHUD") as CanvasLayer).visible, "Planning restores HUD")
	stage.queue_free()
	await process_frame
	if _failures == 0:
		print("Planning mode tests passed")
	quit(0 if _failures == 0 else 1)


func _exercise_edits(planner: Node) -> void:
	var editor: Node = planner.get("objects")
	var controls: Node = planner.get("controls")
	var table := planner.call("_instantiate_asset", TABLE_PATH) as Node3D
	_check(table != null, "Current table model instantiates through catalog")
	if table == null:
		return
	(planner.get("root") as Node3D).add_child(table)
	table.set_meta("planning_scene_path", TABLE_PATH)
	(editor.get("placed") as Array).append(table)
	planner.call("_select", table)
	_check((planner.get("desk_setup_button") as Button).visible, "Desk selection enables setup")
	var transform_before := table.transform
	editor.call("_rotate_selected", 15.0)
	_check(not table.transform.is_equal_approx(transform_before), "Rotate modifies selected object")
	(planner.get("edit_history") as RefCounted).call("undo")
	_check(table.transform.is_equal_approx(transform_before), "Undo restores the object transform")
	controls.call("_open_desk_setup")
	var desk_setup: Node = planner.get("desk_setup")
	_check(desk_setup.get("active"), "Existing desk tools open after decomposition")
	desk_setup.call("close")
	var light := planner.call("_instantiate_asset", LIGHT_PATH) as Node3D
	(planner.get("root") as Node3D).add_child(light)
	light.set_meta("planning_scene_path", LIGHT_PATH)
	(editor.get("placed") as Array).append(light)
	planner.call("_select", light)
	controls.call("_adjust_selected_light", 0.25)
	var spot := light.find_child("Light", true, false) as SpotLight3D
	_check(spot != null and light.has_meta("planning_light_energy"), "Selected light updates persisted settings")
	await process_frame


func _exercise_maps(planner: Node) -> void:
	var storage: RefCounted = planner.get("storage")
	var editor: Node = planner.get("objects")
	var snapshot: Dictionary = storage.call("_collect_layout_data")
	_check(snapshot.get("version") == 5, "Layout retains DTO version 5")
	var light_records: Array = snapshot["objects"].filter(func(record: Dictionary) -> bool: return record["scene"] == LIGHT_PATH)
	_check(light_records.size() == 1 and light_records[0].get("light_energy", 0.0) > 0.0, "Layout captures edited light")
	var name := "codex_planning_regression_%d" % Time.get_ticks_usec()
	(storage.get("map_name_edit") as LineEdit).text = name
	storage.call("save_named_map")
	var path: String = storage.call("_map_path", name)
	_check(FileAccess.file_exists(path), "Named map saves")
	editor.call("clear_layout", false)
	await process_frame
	storage.call("load_named_map", name)
	var restored: Dictionary = storage.call("_collect_layout_data")
	_check(restored == snapshot, "Named map round trip preserves all object records")
	DirAccess.remove_absolute(path)
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
