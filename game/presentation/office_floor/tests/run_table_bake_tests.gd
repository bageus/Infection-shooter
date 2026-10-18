extends SceneTree
const TABLE := preload("res://game/presentation/office_floor/staged_table.gd")
const PIECE := preload("res://game/presentation/office_floor/table_piece.gd")
const EFFECTS := preload("res://game/features/combat/public/impact_effects.gd")
var failures := 0
var shared_mesh := BoxMesh.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var effects := Node3D.new()
	effects.set_script(EFFECTS)
	world.add_child(effects)
	var table := Node3D.new()
	world.add_child(table)
	table.set_script(TABLE)
	table.set("_effects", effects)
	var finals: Array[RigidBody3D] = []
	for index in 3:
		finals.append(_make_piece(world, "Final_%d" % index, true, Vector3(index, 0.2, 0)))
	for body in finals:
		table.call("_settle_piece", body)
	await process_frame
	var baked := world.get_node_or_null("BakedPieces")
	_expect(baked != null and baked.call("count") == 3, "Final pieces are baked into the batch")
	_expect(finals.all(func(body) -> bool: return not is_instance_valid(body) or body.is_queued_for_deletion()), "Baked pieces leave no physics body")
	_expect(_count_bodies(world) == 0, "No RigidBody3D remains for final pieces")
	var multi := baked.get_child(0) as MultiMeshInstance3D
	_expect(multi.multimesh.visible_instance_count == 3, "One MultiMesh draws the three baked pieces")
	for index in 80:
		var body := _make_piece(world, "Soft_%d" % index, false, Vector3(index, 0.2, 2))
		table.call("_settle_piece", body)
	await process_frame
	_expect(baked.call("count") == 3, "Breakable pieces do not touch the baked batch")
	_expect(_count_bodies(world) == EFFECTS.MAX_RETAINED, "The retained cap only frees breakable pieces")
	for index in 200:
		table.call("_settle_piece", _make_piece(world, "Bulk_%d" % index, true, Vector3(index, 0.2, 4)))
	await process_frame
	_expect(baked.call("count") == 203, "Baked batch grows past one chunk without dropping pieces")
	print("Table bake tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _make_piece(world: Node3D, piece_name: String, final: bool, at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(PIECE)
	body.name = piece_name
	body.set("last_stage", final)
	var mesh := MeshInstance3D.new()
	mesh.mesh = shared_mesh
	body.add_child(mesh)
	world.add_child(body)
	body.global_position = at
	return body


func _count_bodies(world: Node) -> int:
	var total := 0
	for child in world.get_children():
		if child is RigidBody3D and not child.is_queued_for_deletion():
			total += 1
	return total


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
