extends SceneTree

const MAIN := preload("res://game/bootstrap/app/main.tscn")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app := MAIN.instantiate()
	root.add_child(app)
	await process_frame
	var planner: Node = app.get("planning_mode")
	planner.set_process(false)
	planner.call("enter")
	await process_frame
	_test_catalog_and_placement(planner)
	_test_edit_commands(planner)
	_test_geometry_and_storage(planner)
	planner.call("exit")
	_check(not paused, "Exiting the planner resumes gameplay")
	app.free()
	await process_frame
	print("Planning tests: %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_catalog_and_placement(planner: Node) -> void:
	var ui := planner.get("ui") as Control
	ui.get_node("Panel/VBox/Tabs/Lighting").emit_signal("pressed")
	var palette := planner.get("palette") as ItemList
	_check(palette.item_count == 3, "Lighting tab displays its catalog")
	palette.item_selected.emit(0)
	_check(planner.get("selected_kind") == "light", "Palette selection activates the light tool")
	_check(planner.get("preview") != null, "Palette selection creates a preview")
	var camera := planner.get("camera") as Camera3D
	var screen := camera.unproject_position(Vector3(5, 0, 5))
	var objects: Variant = planner.get("objects")
	objects._click_world(screen)
	_check(_lamps(planner).size() == 1, "Active tool places a light")
	objects._click_world(screen)
	_check(_lamps(planner).size() == 2, "Repeated click places another light instead of selecting the first")
	var lamp := _lamps(planner)[0]
	_check(is_equal_approx(lamp.position.y, (planner.get("default_light_height") as SpinBox).value), "Ceiling tools keep their authored height")
	planner.get("view")._reset_selection()
	_check(planner.get("preview") == null, "Resetting the tool clears its preview")
	ui.get_node("Panel/VBox/Tabs/Actors").emit_signal("pressed")
	palette.item_selected.emit(0)
	objects._click_world(camera.unproject_position(Vector3(7, 0, 7)))
	_check(bool(planner.get("player_spawn_defined")), "Actor catalog can set the player spawn")
	planner.get("view")._reset_selection()


func _test_edit_commands(planner: Node) -> void:
	var lamp := _lamps(planner)[0]
	planner.call("_select", lamp)
	var energy := float(lamp.call("get_authored_energy"))
	_key(planner, KEY_BRACKETRIGHT)
	_check(is_equal_approx(float(lamp.call("get_authored_energy")), energy + 0.25), "Keyboard input routes brightness to object editing")
	_key(planner, KEY_R)
	_check(is_equal_approx(lamp.rotation_degrees.y, 90.0), "Keyboard rotation reaches the selected object")
	var position := lamp.position
	_key(planner, KEY_RIGHT)
	_check(not lamp.position.is_equal_approx(position), "Keyboard nudge uses the active camera")
	_key(planner, KEY_DELETE)
	_check(_lamps(planner).size() == 1, "Delete removes only the selected light")
	planner.get("edit_history").call("undo")
	_check(_lamps(planner).size() == 2, "History restores a deleted light through the asset catalog")


func _test_geometry_and_storage(planner: Node) -> void:
	var geometry: Variant = planner.get("geometry")
	_check(geometry._snap(Vector3(1.13, 4, 2.37)) == Vector3(1.25, 0, 2.25), "Placement snapping preserves the original grid")
	var camera := planner.get("camera") as Camera3D
	geometry._zoom_camera(-1000)
	_check(is_equal_approx(camera.global_position.y, -15.0), "Planner camera retains its lower bound")
	geometry._zoom_camera(1000)
	_check(is_equal_approx(camera.global_position.y, 55.0), "Planner camera retains its upper bound")
	var storage: Variant = planner.get("storage")
	_check(storage._safe_map_name("  Office / 01  ") == "office_01", "Map-name sanitization remains unchanged")
	var data: Dictionary = planner.call("_collect_layout_data")
	_check(int(data["version"]) == 5, "Serialization retains the existing map version")
	planner.call("_apply_layout_data", JSON.parse_string(JSON.stringify(data)))
	_check(_lamps(planner).size() == 2, "Round-trip preserves both placed lights")
	var markers := planner.get("planning_grid") as MeshInstance3D
	_check(markers != null and markers.mesh != null, "Planner view builds its grid")


func _key(planner: Node, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	planner.call("_input", event)


func _lamps(planner: Node) -> Array[Node3D]:
	var lamps: Array[Node3D] = []
	for node: Node3D in planner.get("placed"):
		if node.has_method("get_authored_energy"):
			lamps.append(node)
	return lamps


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
