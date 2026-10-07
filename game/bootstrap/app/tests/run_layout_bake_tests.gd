extends SceneTree
## Baking the planner map into a scene keeps one copy of each instanced
## structure: its children come back from the instance, not from the bake.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const GLASS_WALL := "res://game/presentation/office_floor/public/structural/glass_wall_full.tscn"
const TARGET := "user://layout_bake_test.tscn"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var planner: Node = stage.get("planning_mode")
	var objects: Variant = planner.get("objects")
	var wall := planner.call("_instantiate_asset", GLASS_WALL) as Node3D
	planner.root.add_child(wall)
	wall.set_meta("planning_scene_path", GLASS_WALL)
	objects.placed.append(wall)
	var fresh := (load(GLASS_WALL) as PackedScene).instantiate()
	var expected := _count(fresh)
	fresh.free()
	for bake in 2:
		_check(planner.storage._save_authored_scene(TARGET) == OK, "The layout bakes")
		var baked := (ResourceLoader.load(TARGET, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var copy := baked.get_child(baked.get_child_count() - 1)
		_check(_count(copy) == expected, "Bake %d keeps one copy of the glass wall (%d nodes, expected %d)" % [bake + 1, _count(copy), expected])
		baked.free()
	DirAccess.remove_absolute(TARGET)
	stage.queue_free()
	await process_frame
	print("Layout bake tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
