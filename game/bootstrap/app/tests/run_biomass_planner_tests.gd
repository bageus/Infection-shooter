extends SceneTree
## ADR-0062 in the planner: the Biomass tab offers an amount slider and an
## "Apply biomass" button; applying lays floor biomass joining the spawn holes,
## replaces the previous network, and undoes in one step.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const SPOTS := [Vector2(470, 230), Vector2(850, 460)]
var failures := 0
var planner: Node
var objects: Node
var controls: Node
var stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + message)
	else:
		print("PASS: " + message)


func _run() -> void:
	stage = MAIN.instantiate() as Node3D
	stage.set("defer_layout_loading", true)
	root.add_child(stage)
	current_scene = stage
	await process_frame
	planner = stage.get("planning_mode")
	planner.enter()
	objects = planner.objects
	controls = planner.controls
	var options: Node = controls.biomass_options
	_check(not options.panel.visible, "the generator is hidden outside the Biomass tab")
	controls._show_biomass_catalog()
	_check(options.panel.visible and options.apply_button.text == "Apply biomass", "the Biomass tab shows the amount slider and the apply button")
	controls._show_gore_catalog()
	_check(not options.panel.visible, "it hides again with the tab")
	controls._show_biomass_catalog()
	var before := _biomass().size()
	options.apply_button.pressed.emit()
	_check(_biomass().size() == before and "spawn hole" in controls.status.text, "without spawn holes nothing is laid and the status says why")
	for spot: Vector2 in SPOTS:
		_check(_place_hole(spot) != null, "spawn hole placed")
	options.amount.value = 30.0
	_check(options.readout.text == "30%", "the slider shows its amount")
	var first: Array[Node3D] = options.apply(5)
	_check(first.size() > 20, "applying lays biomass (%d pieces)" % first.size())
	var floor_view: Node3D = stage.get_node("Floor")
	var bounds := Rect2(-floor_view.get("floor_size") * 0.5, floor_view.get("floor_size"))
	var inside := true
	for node in first:
		inside = inside and bounds.has_point(Vector2(node.global_position.x, node.global_position.z)) and node.call("get_blood_config")["surface"] == "floor"
	_check(inside, "every piece is floor biomass inside the level")
	_check(_biomass().size() == first.size(), "the pieces are planner objects (they save like hand-placed biomass)")
	await process_frame
	await process_frame
	_check(first[0].get("_visual") != null and first[0].has_meta("biomass_piece"), "pieces are real volumetric biomass")
	var second: Array[Node3D] = options.apply(6)
	_check(_biomass().size() == second.size(), "applying again replaces the previous network")
	await process_frame
	_check(not is_instance_valid(first[0]) or first[0].is_queued_for_deletion(), "the old pieces are gone")
	var hand := _biomass().size()
	planner.edit_history.call("undo")
	_check(_biomass().size() == 0 and hand > 0, "one undo removes the whole network")
	stage.queue_free()
	await process_frame
	print("Biomass planner tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _biomass() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node3D in objects.placed:
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_meta("planning_biomass_generated"):
			found.append(node)
	return found


func _place_hole(screen: Vector2) -> Node3D:
	var entry := {}
	for candidate: Dictionary in planner.catalog.actor_catalog:
		if str(candidate.get("path", "")).get_file() == "spawn_point.tscn":
			entry = candidate
	objects._reset_selection()
	objects.selected_path = str(entry.get("path", ""))
	objects.selected_kind = str(entry.get("kind", ""))
	objects.selected_entry = entry
	objects._rebuild_preview()
	var count: int = objects.placed.size()
	objects._place_selected(screen)
	objects._reset_selection()
	return objects.placed.back() if objects.placed.size() > count else null
