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
	await _exercise_gore_palette(planner)
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


# Gore and Blood palettes (ADR-0017); the placed objects then go through the
# named-map round trip below.
func _exercise_gore_palette(planner: Node) -> void:
	var editor: Node = planner.get("objects")
	var controls: Node = planner.get("controls")
	var catalog: Variant = planner.get("catalog")
	controls.call("_show_blood_catalog")
	var blood_entries: Array = catalog.get("active_catalog")
	_check(blood_entries.size() == 45, "Blood palette lists the 45 in-game blood textures")
	_check((controls.get("blood_options") as Control).visible, "Blood palette shows surface and size options")
	(controls.get("blood_surface") as OptionButton).select(1)
	(controls.get("blood_size") as SpinBox).value = 1.6
	var entry: Dictionary = blood_entries[3]
	var blood := planner.call("_instantiate_asset", str(entry["path"])) as Node3D
	controls.call("_configure_new_asset", blood, entry)
	(planner.get("root") as Node3D).add_child(blood)
	blood.set_meta("planning_scene_path", str(entry["path"]))
	(editor.get("placed") as Array).append(blood)
	_check(bool(blood.get_meta("planning_wall_mount", false)), "Wall blood is placed as a wall-mounted object")
	_check(is_equal_approx(blood.scale.x, 1.6), "Blood size comes from the palette option")
	_check(str(blood.call("get_blood_config")["texture"]) == str(entry["blood_texture"]), "Blood keeps the chosen texture")
	controls.call("_show_gore_catalog")
	var gore: Array = catalog.get("active_catalog")
	_check(gore.size() == 28, "Gore palette lists current corpses and body parts (%d)" % gore.size())
	_check(not (controls.get("blood_options") as Control).visible, "Blood options hide outside the Blood palette")
	for index in [0, 1, gore.size() - 1]:
		var decor_entry: Dictionary = gore[index]
		var decor := planner.call("_instantiate_asset", str(decor_entry["path"])) as Node3D
		_check(decor != null, "Gore entry instantiates: " + str(decor_entry["name"]))
		if decor == null:
			continue
		(planner.get("root") as Node3D).add_child(decor)
		decor.set_meta("planning_scene_path", str(decor_entry["path"]))
		(editor.get("placed") as Array).append(decor)
		_check(not decor.find_children("*", "MeshInstance3D", true, false).is_empty(), "Gore entry has visible geometry: " + str(decor_entry["name"]))
	await process_frame


func _exercise_maps(planner: Node) -> void:
	var storage: RefCounted = planner.get("storage")
	var editor: Node = planner.get("objects")
	var snapshot: Dictionary = storage.call("_collect_layout_data")
	_check(snapshot.get("version") == 8, "Layout uses DTO version 8")
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
	if restored != snapshot:
		for i in mini(restored["objects"].size(), snapshot["objects"].size()):
			if restored["objects"][i] != snapshot["objects"][i]:
				print("DIFF ", snapshot["objects"][i], "\n  -> ", restored["objects"][i])
		print("counts ", snapshot["objects"].size(), " ", restored["objects"].size())
	DirAccess.remove_absolute(path)
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

