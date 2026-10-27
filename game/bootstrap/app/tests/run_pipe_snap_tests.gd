extends SceneTree
## Group 01 ducts and water pipes: open ends meet one to one, mounting sides stay flush,
## raised pieces hang from the ceiling.
const SNAP := preload("res://game/bootstrap/app/planning_pipe_snap.gd")
const ROOT := "res://models/objects/enviroments/01/"
const DUCT_BOX := AABB(Vector3(-0.5475, 0, -0.035), Vector3(1.095, 0.8, 2.07))
const ELBOW_BOX := AABB(Vector3(-0.5475, 0, -0.035), Vector3(1.5825, 0.8, 1.5825))
const WALL_PIPE_BOX := AABB(Vector3(-0.1, -0.005, 0), Vector3(0.2, 2.01, 0.3193))
var failures := 0
var stage: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	_test_model_ends()
	_test_straight_ends()
	_test_elbow_chain()
	_test_rejections()
	_test_wall_flush()
	_test_ceiling()
	stage.queue_free()
	await process_frame
	print("Pipe snap tests: %d failures" % failures)
	quit(1 if failures else 0)


func _piece(model: String, position: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> Node3D:
	var node := Node3D.new()
	node.set_meta("planning_scene_path", ROOT + model + ".glb")
	stage.add_child(node)
	node.position = position
	node.rotation.y = yaw
	return node


func _neighbors(nodes: Array) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for node: Node3D in nodes:
		records.append({"node": node, "bounds": DUCT_BOX})
	return records


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


# The ends table must describe the real meshes: vertices lie on the end plane around its centre.
func _test_model_ends() -> void:
	for name: String in SNAP.MODELS:
		var model := (load(ROOT + name + ".glb") as PackedScene).instantiate() as Node3D
		stage.add_child(model)
		var node := _piece(name)
		for end: Dictionary in SNAP.world_ends(node, Vector3.ZERO):
			var normal: Vector3 = end.normal
			var plane: float = (end.pos as Vector3).dot(normal)
			var sum := Vector3.ZERO
			var count := 0
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				var frame := mesh.global_transform
				for surface in mesh.mesh.get_surface_count():
					for vertex: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
						var world := frame * vertex
						if absf(world.dot(normal) - plane) < 0.002:
							sum += world
							count += 1
			_check(count > 0 and (sum / maxf(count, 1.0)).distance_to(end.pos) < 0.02, "Open end of %s sits on the mesh end face" % name)
		model.free()
		node.free()


func _test_straight_ends() -> void:
	var anchor := _piece("01_duct_rect_straight")
	var source := _piece("01_duct_rect_straight", Vector3(0.1, 0, 2.4))
	var result: Variant = SNAP.join(source, source.position, _neighbors([anchor]), false)
	_check(result != null and (result as Vector3).is_equal_approx(Vector3(0, 0, 2.07)), "Straight ducts meet end to end: %s" % str(result))
	# Rotated anchor: the ends follow the piece.
	anchor.rotation.y = PI / 2
	source.position = Vector3(2.4, 0, -0.2)
	source.rotation.y = PI / 2
	result = SNAP.join(source, source.position, _neighbors([anchor]), false)
	_check(result != null and (result as Vector3).is_equal_approx(Vector3(2.07, 0, 0)), "Rotated ducts meet end to end: %s" % str(result))
	source.position = Vector3(5, 0, 5)
	_check(SNAP.join(source, source.position, _neighbors([anchor]), false) == null, "A distant duct does not snap")
	anchor.free()
	source.free()


func _test_elbow_chain() -> void:
	var anchor := _piece("01_duct_rect_straight")
	var elbow := _piece("01_duct_rect_elbow", Vector3(0.2, 0, 2.2))
	var result: Variant = SNAP.join(elbow, elbow.position, _neighbors([anchor]), false)
	_check(result != null and (result as Vector3).is_equal_approx(Vector3(0, 0, 2.07)), "Elbow start meets the straight end")
	# Turned a quarter, the elbow's other end faces the straight.
	elbow.rotation.y = PI / 2
	elbow.position = Vector3(-0.9, 0, 3.0)
	result = SNAP.join(elbow, elbow.position, _neighbors([anchor]), false)
	_check(result != null and (result as Vector3).is_equal_approx(Vector3(-1.0, 0, 3.07)), "Elbow second end joins the straight: %s" % str(result))
	var pipe := _piece("01_pipe_water_floor_straight", Vector3(0, 0, 2.2))
	_check(SNAP.join(pipe, pipe.position, _neighbors([anchor]), false) == null, "Water pipe never joins a duct")
	anchor.free()
	elbow.free()
	pipe.free()


func _test_rejections() -> void:
	var anchor := _piece("01_duct_rect_straight")
	var side := _piece("01_duct_rect_straight", Vector3(0, 0, 2.2), PI / 2)
	_check(SNAP.join(side, side.position, _neighbors([anchor]), false) == null, "Ends that are not opposite never join")
	var high := _piece("01_duct_rect_straight", Vector3(0, 1.0, 2.2))
	_check(SNAP.join(high, high.position, _neighbors([anchor]), false) == null, "Ends at another height never join")
	anchor.free()
	side.free()
	high.free()


func _test_wall_flush() -> void:
	var anchor := _piece("01_pipe_water_wall_straight", Vector3(0, 0.5, 0.005))
	anchor.set_meta("planning_wall_mount", true)
	anchor.set_meta("planning_wall_normal", Vector3.BACK)
	var source := _piece("01_pipe_water_wall_straight", Vector3(0.1, 2.8, 0.02))
	source.set_meta("planning_wall_mount", true)
	source.set_meta("planning_wall_normal", Vector3.BACK)
	var result: Variant = SNAP.join(source, source.position, _neighbors([anchor]), true)
	_check(result != null and absf((result as Vector3).z - 0.02) < 0.0001, "Wall pipes keep their mounting plane while joining")
	_check(result != null and absf((result as Vector3).x) < 0.0001 and absf((result as Vector3).y - 2.51) < 0.0001, "Wall pipes join top to bottom: %s" % str(result))
	var floor_piece := _piece("01_pipe_water_wall_straight", Vector3(0.1, 2.8, 0.02))
	_check(SNAP.join(floor_piece, floor_piece.position, _neighbors([anchor]), false) == null, "A free pipe never joins a wall-mounted one")
	source.set_meta("planning_wall_normal", Vector3.RIGHT)
	_check(SNAP.join(source, source.position, _neighbors([anchor]), true) == null, "Pipes on different walls never join")
	anchor.free()
	source.free()
	floor_piece.free()


func _test_ceiling() -> void:
	var duct := _piece("01_duct_rect_straight", Vector3(1, 2.1, 1))
	_check(not SNAP.on_ceiling(duct), "A floor duct starts with its mounting side down")
	_check(SNAP.settle_ceiling(duct, DUCT_BOX), "A raised duct attaches to the ceiling")
	var top := (duct.global_transform * DUCT_BOX).end.y
	_check(SNAP.on_ceiling(duct) and absf(top - (SNAP.CEILING_Y - SNAP.CEILING_CLEARANCE)) < 0.0001, "Mounting side is up and flush with the ceiling: %f" % top)
	var ends := SNAP.world_ends(duct, duct.global_position)
	_check((ends[0].pos as Vector3).is_equal_approx(Vector3(1, 2.8 - 0.002 - 0.4, 1 - 0.035)) and absf((ends[0].pos as Vector3).z - (ends[1].pos as Vector3).z) > 2.0, "A half turn keeps the run straight")
	duct.position.y -= 0.25
	_check(not SNAP.settle_ceiling(duct, DUCT_BOX) and not SNAP.on_ceiling(duct), "Lowering the duct releases it and flips it back")
	_check(absf((duct.global_transform * DUCT_BOX).get_center().y - (2.8 - 0.002 - 0.4 - 0.25)) < 0.0001, "Releasing keeps the height")
	duct.free()
	var elbow := _piece("01_duct_rect_elbow", Vector3(0, 2.2, 0))
	var before := SNAP.world_ends(elbow, elbow.global_position)
	SNAP.settle_ceiling(elbow, ELBOW_BOX)
	var after := SNAP.world_ends(elbow, elbow.global_position)
	_check(SNAP.on_ceiling(elbow), "Raised elbow hangs from the ceiling")
	_check((before[0].pos as Vector3).x - (after[1].pos as Vector3).x == 0.0 or absf((before[0].pos as Vector3).x - (after[1].pos as Vector3).x) < 0.0001, "A flipped elbow keeps its footprint")
	elbow.free()
	var low := _piece("01_duct_rect_straight", Vector3(0, 0, 0))
	_check(not SNAP.settle_ceiling(low, DUCT_BOX) and not SNAP.on_ceiling(low), "A duct on the floor stays put")
	low.free()
	var wall := _piece("01_pipe_water_wall_straight", Vector3(0, 1.0, 0))
	wall.set_meta("planning_wall_mount", true)
	_check(not SNAP.settle_ceiling(wall, WALL_PIPE_BOX), "A wall-mounted pipe is never turned")
	wall.free()
