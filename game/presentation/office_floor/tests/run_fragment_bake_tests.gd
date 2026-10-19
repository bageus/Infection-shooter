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
	await process_frame
	await process_frame
	final.call("expire")
	keep.call("expire")
	await process_frame
	_expect(baked.call("count") == 1, "A final fragment bakes into the floor batch")
	_expect(not is_instance_valid(final) or final.is_queued_for_deletion(), "A baked fragment frees its body")
	_expect(is_instance_valid(keep) and not keep.is_queued_for_deletion(), "A breakable fragment stays where it landed")
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
