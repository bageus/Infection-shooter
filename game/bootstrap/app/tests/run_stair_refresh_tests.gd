extends SceneTree
## O01: equivalent holes/physics with no periodic search through furniture.
const LAYOUT := preload("res://game/bootstrap/app/mission_layout.gd")
const STAIR := preload("res://game/presentation/office_floor/public/structural/staircase.tscn")
const STAIR_PATH := "res://models/objects/enviroments/01/01_stairs.glb"
var failures := 0
var stage: Node3D
var objects: Node3D
var layout: ObservedLayout
var floor_view: FloorView
var floor_body: StaticBody3D
var oracle: Node3D

class Furniture:
	extends Node3D
	var path_reads := 0
	var model_path: String:
		get:
			path_reads += 1
			return "res://models/objects/enviroments/08/08_desk.glb"

class FloorView:
	extends Node3D
	var openings: Array[Rect2] = []
	var updates := 0
	func set_stair_openings(value: Array[Rect2]) -> void:
		openings.assign(value)
		updates += 1

class ObservedLayout:
	extends "res://game/bootstrap/app/mission_layout.gd"
	var geometry_builds := 0
	var bounds_checks := 0
	func _stair_openings(stair: Node3D, bounds: AABB) -> Array[Rect2]:
		geometry_builds += 1
		return super._stair_openings(stair, bounds)
	func _visual_bounds(stair: Node3D) -> AABB:
		bounds_checks += 1
		return super._visual_bounds(stair)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var benchmark := OS.get_cmdline_user_args().has("--benchmark")
	_fixture(5424 if benchmark else 0)
	if benchmark:
		_benchmark()
	else:
		await _empty_and_static()
		await _real_stair_edits()
		await _late_metadata_and_mesh_edits()
		await _remove_reload_and_teardown()
	oracle.free()
	stage.queue_free()
	await process_frame
	await process_frame
	print("Stair refresh tests: %d failures" % failures)
	quit(1 if failures else 0)


func _fixture(furniture_count: int) -> void:
	stage = Node3D.new()
	root.add_child(stage)
	objects = Node3D.new()
	objects.name = "PlanningObjects"
	stage.add_child(objects)
	floor_view = FloorView.new()
	floor_view.name = "Floor"
	stage.add_child(floor_view)
	floor_body = StaticBody3D.new()
	floor_body.name = "FloorBody"
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(80, .2, 60)
	collision.shape = box
	collision.position.y = -.1
	floor_body.add_child(collision)
	stage.add_child(floor_body)
	for index in furniture_count:
		objects.add_child(Furniture.new())
	layout = ObservedLayout.new()
	stage.add_child(layout)
	layout.setup(stage, null, null)
	layout.set_process(false)
	oracle = LAYOUT.new()


func _sync() -> void:
	# Deferred registration must see transforms/metadata assigned after add_child.
	await process_frame
	await process_frame
	layout._process(.35)
	layout.set_process(false)
	await physics_frame
	await physics_frame


func _reference_openings() -> Array[Rect2]:
	# The pre-optimization full scan, using the unchanged geometric functions.
	var expected: Array[Rect2] = []
	for child in objects.get_children():
		if not child is Node3D or child.is_queued_for_deletion():
			continue
		var path := str(child.get_meta("planning_scene_path", ""))
		if path.is_empty():
			path = str(child.get("model_path"))
		if path.get_file() not in ["01_stairs.glb", "01_stairs_2.glb"]:
			continue
		var bounds: AABB = oracle.call("_visual_bounds", child)
		if bounds.size.length_squared() < .01 or bounds.position.y > -.4 or bounds.end.y < -.05:
			continue
		expected.append_array(oracle.call("_stair_openings", child, bounds))
	return expected


func _equivalent(label: String) -> void:
	var expected := _reference_openings()
	_check(layout.get("_openings") == expected, label + ": exact ordered holes match the full scan")
	_check(floor_view.openings == expected, label + ": visible floor uses those holes")
	_check((floor_body.get_node("CollisionShape3D") as CollisionShape3D).disabled == not expected.is_empty(), label + ": original floor collision mode matches")
	var excluded: Array[RID] = []
	for body in objects.find_children("*", "StaticBody3D", true, false):
		excluded.append((body as StaticBody3D).get_rid())
	for opening in expected:
		var point := opening.get_center()
		_check(layout.goal_reached(Vector3(point.x, -2, point.y)), label + ": hole remains an exit below floor")
		_check(not layout.goal_reached(Vector3(point.x, -1.3, point.y)), label + ": exit height threshold unchanged")
		_check(not _floor_hit(point, excluded), label + ": floor physics has a hole")
	_check(_floor_hit(Vector2(35, 25), excluded), label + ": distant floor remains solid")
	_check(not layout.goal_reached(Vector3(35, -2, 25)), label + ": solid floor is not an exit")


func _floor_hit(point: Vector2, excluded: Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, .2, point.y), Vector3(point.x, -.4, point.y), 1, excluded)
	var hit := floor_body.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == floor_body


func _empty_and_static() -> void:
	var furniture := Furniture.new()
	objects.add_child(furniture)
	await _sync()
	var reads := furniture.path_reads
	var updates := floor_view.updates
	for tick in 100:
		layout._process(.35)
	_check(furniture.path_reads == reads, "Unchanged furniture is never inspected again")
	_check(floor_view.updates == updates, "Empty map does not rebuild floor geometry")
	# Remove the test's manual process override, then verify production scheduling.
	layout.set_process(true)
	layout._refresh_stairs()
	_check(not layout.is_processing(), "No stair registry means no per-frame callback")
	await _sync()
	_equivalent("No stairs")
	furniture.free()


func _spawn_stair(position: Vector3, legacy := false) -> Node3D:
	var stair := STAIR.instantiate() as Node3D
	stair.position = position
	objects.add_child(stair)
	stair.set_meta("planning_scene_path", STAIR_PATH.replace("01_stairs.glb", "01_stairs_2.glb") if legacy else STAIR_PATH)
	return stair


func _real_stair_edits() -> void:
	var stair := _spawn_stair(Vector3(0, -3, 0))
	await _sync()
	_check(not floor_view.openings.is_empty(), "Real descending staircase opens the floor")
	_equivalent("Initial real staircase")
	var furniture := Furniture.new()
	objects.add_child(furniture)
	await _sync()
	var reads := furniture.path_reads
	var geometry := layout.geometry_builds
	var updates := floor_view.updates
	for tick in 20:
		layout._process(.35)
	_check(furniture.path_reads == reads, "Furniture stays uninspected even with live stair openings")
	_check(layout.geometry_builds == geometry, "Stable stair inputs reuse expensive opening geometry")
	_check(floor_view.updates == updates, "Stable stairs do not rebuild visual/physical floor")
	for pose in [Vector3(6, -3, 2), Vector3(6, 1, 2), Vector3(-4, -3, 2)]:
		stair.position = pose
		await _sync()
		_equivalent("Moved/upstairs staircase")
	stair.rotation.y = PI / 2
	stair.scale = Vector3.ONE * 1.2
	await _sync()
	_equivalent("Rotation and uniform scale")
	objects.position = Vector3(3, 0, -2)
	await _sync()
	_equivalent("Parent transform")
	objects.position = Vector3.ZERO
	var second := _spawn_stair(Vector3(12, -3, 4), true)
	await _sync()
	_equivalent("Canonical and legacy staircase together")
	objects.move_child(second, 0)
	await _sync()
	_equivalent("Explicit child reorder")


func _late_metadata_and_mesh_edits() -> void:
	var stair := Node3D.new()
	objects.add_child(stair)
	stair.set_meta("planning_scene_path", STAIR_PATH)
	stair.position = Vector3(-12, -3, -4)
	var visual := MeshInstance3D.new()
	visual.mesh = BoxMesh.new()
	(visual.mesh as BoxMesh).size = Vector3(4, 3, 6)
	visual.position = Vector3(0, 1.5, 1.4)
	stair.add_child(visual)
	await _sync()
	_equivalent("Late metadata and visual setup")
	stair.scale = Vector3(1.2, 1, .8) # Geometry-only fixture has no scaled Jolt body.
	await _sync()
	_equivalent("Nonuniform scale input")
	var holes := floor_view.openings.size()
	visual.position.y += 10
	await _sync()
	_check(floor_view.openings.size() < holes, "Visual bounds changes invalidate the cached openings")
	_equivalent("Visual moved to upstairs")
	(visual.mesh as BoxMesh).size.y = 30
	await _sync()
	_equivalent("Shared mesh bounds changed")
	var highlight := MeshInstance3D.new()
	highlight.mesh = BoxMesh.new()
	(highlight.mesh as BoxMesh).size = Vector3(200, 200, 200)
	highlight.set_meta("planning_selection_highlight", true)
	stair.add_child(highlight)
	var builds := layout.geometry_builds
	await _sync()
	_check(layout.geometry_builds == builds, "Selection overlay does not invalidate real geometry")
	_equivalent("Selection overlay ignored")


func _remove_reload_and_teardown() -> void:
	var removed := objects.get_child(0) as Node3D
	objects.remove_child(removed)
	await _sync()
	_equivalent("Detached stair")
	objects.add_child(removed)
	await _sync()
	_equivalent("Undo reattaches stair")
	for child in objects.get_children():
		child.queue_free()
	await _sync()
	_equivalent("Clear all staircases")
	layout.set_process(true)
	layout._refresh_stairs()
	_check(not layout.is_processing(), "Last removal shuts down periodic processing")
	var ephemeral := _spawn_stair(Vector3(2, -3, 0))
	ephemeral.free() # Gone before its deferred registration.
	await _sync()
	_equivalent("Removed before registration")
	_spawn_stair(Vector3(2, -3, 0))
	await _sync()
	_equivalent("Reload populated map")
	layout.free()
	_check(objects.child_entered_tree.get_connections().is_empty() and objects.child_exiting_tree.get_connections().is_empty(), "Layout teardown disconnects observers")
	var post_teardown := Furniture.new()
	objects.add_child(post_teardown)
	await process_frame
	post_teardown.free()
	layout = ObservedLayout.new()
	stage.add_child(layout)
	layout.setup(stage, null, null)
	await _sync()
	_equivalent("Existing baked stairs at setup")
	layout.free()


func _benchmark() -> void:
	for warmup in 5:
		layout._refresh_stairs()
	var before := _read_count()
	var samples: Array[int] = []
	for index in 100:
		var start := Time.get_ticks_usec()
		layout._refresh_stairs()
		samples.append(Time.get_ticks_usec() - start)
	samples.sort()
	var total := 0
	for sample in samples:
		total += sample
	print("STAIR_BENCH ", JSON.stringify({"objects": 5424, "runs": 100, "mean_usec": float(total) / 100, "p95_usec": samples[94], "furniture_path_reads": _read_count() - before}))


func _read_count() -> int:
	var result := 0
	for child in objects.get_children():
		if child is Furniture:
			result += child.path_reads
	return result


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
