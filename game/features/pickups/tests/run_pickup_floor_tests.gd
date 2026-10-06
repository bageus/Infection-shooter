extends SceneTree

const PICKUP := preload("res://game/features/pickups/pickup_item.gd")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 0.2, 10)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.1
	await physics_frame
	var items: Array[Node3D] = []
	for offset in [-0.3, 0.0, 1.5]:
		var item := PICKUP.new() as Area3D
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.4, 0.4, 0.4)
		visual.mesh = mesh
		visual.position.y = offset + 0.2
		item.add_child(visual)
		stage.add_child(item)
		item.position = Vector3(0, 1.2, 0)
		item.call("settle_on_floor")
		items.append(item)
	await physics_frame
	await physics_frame
	for item in items:
		var bottom := item.global_position.y + float(item.call("_visual_bottom_offset"))
		_expect(is_equal_approx(bottom, 0.018), "Different mesh origins rest on the floor with only the tile clearance.")
		_expect(not item.is_physics_processing(), "Settled pickups do not query surfaces every frame.")
	var empty_drop := PICKUP.new() as Area3D
	stage.add_child(empty_drop)
	empty_drop.position = Vector3(100, 1, 100)
	var reference: WeakRef = weakref(empty_drop)
	empty_drop.call("settle_on_floor")
	await physics_frame
	await physics_frame
	await process_frame
	_expect(not is_instance_valid(reference.get_ref()), "A missing floor does not leave a floating pickup.")
	stage.queue_free()
	print("Pickup floor tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
