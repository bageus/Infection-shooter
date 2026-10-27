extends SceneTree

const TEMPLATES := preload("res://game/bootstrap/app/planning_group_templates.gd")
const LOADER := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const TABLE_PATH := "res://models/objects/enviroments/07/07_table.glb"
const TEST_NAME := "unit_test_group"
var _failures := 0


func _initialize() -> void:
	_check_pure_functions()
	call_deferred("_run_planner_flow")


func _check_pure_functions() -> void:
	var records: Array = [
		{"scene": "res://a.glb", "x": 10.0, "y": 1.0, "z": 4.0, "rotation_y": 0.0, "spawn_x": 10.0, "spawn_y": 1.0, "spawn_z": 4.0, "object_id": "object_1", "desk_id": "7"},
		{"scene": "res://b.glb", "x": 12.0, "y": 0.5, "z": 8.0, "rotation_y": 90.0, "zone": -1},
	]
	var template := TEMPLATES.make_template("Test group", records)
	var first: Dictionary = template.objects[0]
	# Centre is (11, 6) on x/z and the lowest floor is 0.5.
	_check(template.objects.size() == 2, "Template keeps every object")
	_check(is_equal_approx(first.x, -1.0) and is_equal_approx(first.z, -2.0) and is_equal_approx(first.y, 0.5), "Positions become offsets from the group centre")
	_check(not first.has("object_id") and not first.has("desk_id") and not first.has("zone"), "Source identity and desk links are dropped")
	var placed: Dictionary = TEMPLATES.moved(first, Vector3(20.0, 0.0, 30.0), 90.0)
	_check(is_equal_approx(placed.x, 18.0) and is_equal_approx(placed.z, 31.0) and is_equal_approx(placed.y, 0.5), "Placement turns the offset around the anchor")
	_check(is_equal_approx(placed.rotation_y, 90.0), "Placement adds the group yaw to each object")
	_check(is_equal_approx(placed.spawn_x, 18.0) and is_equal_approx(placed.spawn_z, 31.0), "Spawn positions move with the object")
	_check(TEMPLATES.write(TEST_NAME, template), "Template file is written")
	var loaded: Dictionary = TEMPLATES.load_template(TEMPLATES.ROOT + "/" + TEST_NAME + ".json")
	_check(loaded.get("name") == "Test group" and (loaded.objects as Array).size() == 2, "Template file reads back")
	_check(TEMPLATES.load_template("user://elsewhere/" + TEST_NAME + ".json").is_empty(), "Files outside the template folder are refused")
	DirAccess.remove_absolute(TEMPLATES.ROOT + "/" + TEST_NAME + ".json")


## Recording keeps only objects placed in the mode, and a saved group ghosts and loads back.
func _run_planner_flow() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	await physics_frame
	stage.call("_on_planning_pressed")
	var planner: Node = stage.get("planning_mode")
	var objects: Node = planner.get("objects")
	var templates: Node = planner.get("controls").get("group_templates")
	var table := planner.call("_instantiate_asset", TABLE_PATH) as Node3D
	(planner.get("root") as Node3D).add_child(table)
	table.set_meta("planning_scene_path", TABLE_PATH)
	(objects.get("placed") as Array).append(table)
	# A duplicate is placed without any recording hook; it is still picked and saved, and the unpicked table is not.
	var copy := planner.call("_instantiate_asset", TABLE_PATH) as Node3D
	(planner.get("root") as Node3D).add_child(copy)
	copy.set_meta("planning_scene_path", TABLE_PATH)
	(objects.get("placed") as Array).append(copy)
	var unpicked := planner.call("_instantiate_asset", TABLE_PATH) as Node3D
	(planner.get("root") as Node3D).add_child(unpicked)
	unpicked.set_meta("planning_scene_path", TABLE_PATH)
	(objects.get("placed") as Array).append(unpicked)
	templates.name_edit.text = "Flow group"
	templates._create_pressed()
	templates.toggle_pick(table)
	templates.toggle_pick(copy)
	templates._create_pressed()
	_check(templates.list.item_count >= 1, "Saved template appears in the Templates list")
	var saved := TEMPLATES.load_template(TEMPLATES.ROOT + "/flow_group.json")
	_check((saved.get("objects", []) as Array).size() == 2, "Shift-picked objects are saved, duplicates included, and unpicked ones are not")
	templates.list.select(_index_of(templates.list, "Flow group"))
	templates._edit_pressed()
	_check(templates.recording() and templates.name_edit.text == "Flow group", "Edit opens the saved template for changes")
	templates._cancel_recording()
	_check(not templates.recording(), "Cancel leaves the template mode")
	templates.list.select(_index_of(templates.list, "Flow group"))
	templates._template_selected(templates.list.get_selected_items()[0])
	_check(objects.get("selected_kind") == TEMPLATES.KIND and objects.get("preview") != null, "Choosing a template starts a ghost")
	_check((objects.get("preview") as Node3D).get_child_count() == 2, "Ghost holds every saved object")
	var before: int = (objects.get("placed") as Array).size()
	var count: int = LOADER.new(objects).append([TEMPLATES.moved(saved.objects[0], Vector3(4.0, 0.0, 4.0), 0.0)])
	_check(count == 1 and (objects.get("placed") as Array).size() == before + 1, "Loader places the moved template record")
	DirAccess.remove_absolute(TEMPLATES.ROOT + "/flow_group.json")
	stage.queue_free()
	await process_frame
	if _failures == 0:
		print("Group template tests passed")
	quit(0 if _failures == 0 else 1)


func _index_of(list: ItemList, text: String) -> int:
	for index in list.item_count:
		if list.get_item_text(index) == text:
			return index
	return 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAILED: " + message)
		print("FAILED: " + message)
