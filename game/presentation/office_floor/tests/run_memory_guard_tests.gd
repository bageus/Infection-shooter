extends SceneTree
const GUARD := preload("res://game/core/vfx/public/memory_guard.gd")
const RECEIVER := preload("res://game/presentation/office_floor/receiver_decal_bake.gd")
var failures := 0


func _initialize() -> void:
	GUARD.available_override = 50 * 1024 * 1024
	_check(GUARD.low(true), "Under 200 MiB free is low")
	var bake := RECEIVER.new()
	var anchor := MeshInstance3D.new()
	anchor.mesh = BoxMesh.new()
	_check(not bake.stamp(anchor, Vector3.ZERO, Vector3.UP, "bullet", 0, 0.1, 1.0), "Receiver decals are refused while memory is low")
	_check(bake.queue.is_empty(), "A refused decal queues nothing")
	GUARD.available_override = 4 * 1024 * 1024 * 1024
	_check(not GUARD.low(true), "Plenty of free memory is not low")
	GUARD.available_override = -1
	_check(not GUARD.low(true), "Unknown free memory is never low")
	GUARD.available_override = -2
	anchor.free()
	print("Memory guard tests: %d failure(s)" % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
