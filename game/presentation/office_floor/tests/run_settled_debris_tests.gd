extends SceneTree
const DEBRIS := preload("res://game/presentation/office_floor/debris_lifecycle.gd")
const RUNTIME_STEP := 0.5
var failures := 0


class Host extends Node3D:
	var effects_root: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _settling()
	print("Settled debris tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _settling() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var host := Host.new()
	host.effects_root = world
	world.add_child(host)
	DEBRIS.spawn_chunks(host, AABB(Vector3.ZERO, Vector3.ONE), Color.RED, 4, Vector3.UP, Vector3.ZERO)
	await process_frame
	var runtime := world.get_node("FragmentRuntime")
	var batch := runtime.get_node("SettledPieces/SettledPieces") as MultiMeshInstance3D
	var pieces: Array[RigidBody3D] = []
	for child in world.get_children():
		if child is RigidBody3D:
			child.sleeping = true
			pieces.append(child)
	# No player is in this scene, so the far threshold (5 s) applies.
	runtime.call("settle_resting", 4.0)
	_expect(batch.multimesh.visible_instance_count == 0, "Pieces are not folded before they have rested long enough")
	runtime.call("settle_resting", 1.5)
	_expect(batch.multimesh.visible_instance_count == 4, "Resting pieces fold into the batch")
	_expect(runtime.get("active").is_empty(), "Folded pieces leave the active budget")
	_expect(pieces.all(func(piece: RigidBody3D) -> bool: return not piece.visible and not piece.is_inside_tree()), "Folded pieces return to the pool")
	_expect(batch.multimesh.get_instance_color(0).g < 0.1, "Folded piece keeps its tint (red chunk)")
	var settled: Node3D = runtime.get_node("SettledPieces")
	for index in 252:
		settled.call("add", Transform3D.IDENTITY, Color.WHITE)
	_expect(settled.call("count") == 256, "Batch fills up to its capacity")
	_expect(not settled.call("add", Transform3D.IDENTITY, Color.WHITE), "Batch refuses pieces when full")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
