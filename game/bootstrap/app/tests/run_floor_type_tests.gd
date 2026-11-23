extends SceneTree

const FLOOR_TYPE := preload("res://game/bootstrap/app/planning_floor_type.gd")
const MAIN := preload("res://game/bootstrap/app/main.tscn")
var _failures := 0


func _initialize() -> void:
	_check(FLOOR_TYPE.valid("tile") and FLOOR_TYPE.valid("concrete"), "Both floor types are valid")
	_check(FLOOR_TYPE.valid("wood") and FLOOR_TYPE.valid("carpet") and FLOOR_TYPE.valid("lab_tile"), "Wood, carpet and lab tile are valid")
	_check(not FLOOR_TYPE.valid("lava") and not FLOOR_TYPE.valid(3) and not FLOOR_TYPE.valid(null), "Unknown types are refused")
	_check(FLOOR_TYPE.valid_areas([[20, 15, "wood"]]) and FLOOR_TYPE.valid_areas([]), "Whole-cell painted areas are valid")
	_check(not FLOOR_TYPE.valid_areas([[1.5, 2, "wood"]]) and not FLOOR_TYPE.valid_areas([[1, 2, "lava"]]) and not FLOOR_TYPE.valid_areas([[1, 2]]), "Fractional cells, unknown types and short areas are refused")
	call_deferred("_run_planner_flow")


## The type is applied to the floor material, captured back, saved with the map, and reset by a map without it.
func _run_planner_flow() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	await physics_frame
	stage.call("_on_planning_pressed")
	var planner: Node = stage.get("planning_mode")
	var floor_view := stage.get_node("Floor") as Node3D
	_check(FLOOR_TYPE.capture(planner) == "tile", "A new level has the tile floor")
	var tile_sections := _sections(floor_view)
	_check(not tile_sections.is_empty() and not _concrete(tile_sections[0]), "Tile sections do not use the concrete look")
	FLOOR_TYPE.restore(planner, "concrete")
	_check(FLOOR_TYPE.capture(planner) == "concrete", "Concrete is captured back from the floor")
	_check(_sections(floor_view).all(func(s: MultiMeshInstance3D) -> bool: return _concrete(s)), "Every section takes the concrete look")
	var data: Dictionary = preload("res://game/bootstrap/app/planning_layout_capture.gd").collect(planner.get("objects"), [])
	_check(data.get("floor_type_v1") == "concrete", "The layout record carries the floor type")
	_check(preload("res://game/bootstrap/app/planning_layout_validator.gd").error(data) == "", "The saved record validates")
	data["floor_type_v1"] = "lava"
	_check(preload("res://game/bootstrap/app/planning_layout_validator.gd").error(data) == "invalid floor_type_v1", "An unknown saved type is rejected")
	var group_button := planner.get("ui").get_node("Panel/VBox/GroupTabs/GFloor") as Button
	group_button.pressed.emit()
	var panel := planner.get("controls").floor_type.panel as Control
	_check(panel.visible, "The Floor group shows its options")
	planner.get("controls").call("_show_structure_group", "01")
	_check(not panel.visible, "Another group hides the Floor options")
	FLOOR_TYPE.restore(planner, "")
	_check(FLOOR_TYPE.capture(planner) == "tile", "A map without a type restores tile")
	FLOOR_TYPE.restore(planner, "concrete")
	_check(floor_view.call("paint_floor_cell", Vector2(0, 0), "wood"), "A cell is painted")
	_check(not floor_view.call("paint_floor_cell", Vector2(0, 0), "wood"), "Painting the same look again changes nothing")
	_check(not floor_view.call("paint_floor_cell", Vector2(1000, 0), "wood"), "A cell off the floor is refused")
	var looks := _sections(floor_view).map(func(s: MultiMeshInstance3D) -> int: return int((s.material_override as ShaderMaterial).get_shader_parameter("look")))
	_check(looks.has(2) and looks.has(1), "A painted cell shows wood beside the concrete floor")
	var areas := FLOOR_TYPE.capture_areas(planner)
	_check(areas.size() == 1 and areas[0][2] == "wood", "The painted cell is captured")
	var saved := preload("res://game/bootstrap/app/planning_layout_capture.gd").collect(planner.get("objects"), [])
	_check(saved.get("floor_areas_v1") == areas, "The layout record carries the painted cells")
	_check(preload("res://game/bootstrap/app/planning_layout_validator.gd").error(saved) == "", "A record with painted cells validates")
	var before := FLOOR_TYPE.capture_areas(planner)
	var brush: Node = planner.get("controls").floor_type
	brush.picker.select(2)
	brush.paint_at(root.get_visible_rect().size * 0.5)
	_check(FLOOR_TYPE.capture_areas(planner) != before, "A click at the centre of the view paints the floor under it")
	FLOOR_TYPE.restore_areas(planner, [])
	_check(FLOOR_TYPE.capture_areas(planner).is_empty(), "Restoring no cells clears the paint")
	stage.queue_free()
	await process_frame
	if _failures == 0:
		print("Floor type tests passed")
	quit(0 if _failures == 0 else 1)


func _sections(floor_view: Node) -> Array:
	return floor_view.get_children().filter(func(n: Node) -> bool: return n is MultiMeshInstance3D)


func _concrete(section: MultiMeshInstance3D) -> bool:
	return int((section.material_override as ShaderMaterial).get_shader_parameter("look")) == 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAILED: " + message)
		print("FAILED: " + message)
