extends SceneTree
const FRAGMENT := preload("res://game/presentation/office_floor/environment_fragment.gd")
const RUNTIME := preload("res://game/presentation/office_floor/fragment_runtime.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var effects := Node3D.new()
	root.add_child(effects)
	var runtime := RUNTIME.new()
	runtime.name = "FragmentRuntime"
	effects.add_child(runtime)
	var baked := runtime.get("_baked") as Node
	var final := _make_fragment(effects, Vector3(0, 0.2, 0), false)
	var keep := _make_fragment(effects, Vector3(1, 0.2, 0), true)
	var squeezed := _make_fragment(effects, Vector3(3, 0.2, 0), true)
	await process_frame
	await process_frame
	final.set("sleeping", true)
	var airborne := _make_fragment(effects, Vector3(2, 1.5, 0), false)
	airborne.set("sleeping", true)
	keep.set("sleeping", true)
	squeezed.set("sleeping", true)
	await process_frame
	final.call("expire")
	keep.call("expire")
	airborne.call("expire")
	squeezed.call("expire_fast")
	await process_frame
	_expect(not is_instance_valid(final) or final.is_queued_for_deletion(), "A baked fragment frees its body")
	_expect(baked.call("count") == 3, "Final, airborne and budget-expired fragments all bake; none just vanishes")
	_expect(not keep.has_meta("debris_fading"), "A resting breakable fragment stays when its timer ends")
	_expect(not is_instance_valid(airborne) or not airborne.has_meta("debris_fading"), "An airborne fragment is baked, not shrunk away")
	_expect(not is_instance_valid(squeezed) or not squeezed.has_meta("debris_fading"), "A breakable fragment is baked when the budget is full")
	var multi := baked.get_child(0) as MultiMeshInstance3D
	var lowest := INF
	for index in multi.multimesh.visible_instance_count:
		lowest = minf(lowest, multi.multimesh.get_instance_transform(index).origin.y)
	_expect(lowest > -0.2, "A baked airborne fragment lands on the floor, not in mid-air")
	var top := 0.0
	for index in multi.multimesh.visible_instance_count:
		top = maxf(top, multi.multimesh.get_instance_transform(index).origin.y)
	_expect(top < 0.6, "A baked airborne fragment is dropped from its flight height")
	print("Fragment bake tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _make_fragment(effects: Node3D, at: Vector3, breakable: bool) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(FRAGMENT)
	body.set("breakable", breakable)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	body.add_child(mesh)
	effects.add_child(body)
	body.global_position = at
	return body


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
