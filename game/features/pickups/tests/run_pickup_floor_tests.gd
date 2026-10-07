extends SceneTree

const PICKUP := preload("res://game/features/pickups/pickup_item.gd")
const DROPS := preload("res://game/features/pickups/public/drop_table.gd")
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
	await _test_drops_spread(stage)
	stage.queue_free()
	print("Pickup floor tests: %d failure(s)." % failures)
	quit(failures)


# Kills on one spot leave half-size drops side by side, never overlapping
# and never behind the wall next to the kill.
func _test_drops_spread(stage: Node3D) -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 3.0, 10.0)
	shape.shape = box
	wall.add_child(shape)
	stage.add_child(wall)
	wall.position = Vector3(1.0, 1.5, 0.0)
	await physics_frame
	var table := DROPS.new()
	table.set("any_drop_chance", 1.0)
	stage.add_child(table)
	for i in 6:
		table.call("drop_for_enemy", stage, Vector3(0.6, 0.9, 0.0))
	await physics_frame
	await physics_frame
	var drops: Array[Node] = get_nodes_in_group(DROPS.DROP_GROUP).filter(func(node: Node) -> bool: return is_instance_valid(node) and not node.is_queued_for_deletion())
	_expect(drops.size() == 6, "Every drop finds a place (%d)." % drops.size())
	for i in drops.size():
		var drop := drops[i] as Node3D
		_expect(drop.global_position.x < 1.0, "Drops stay on the kill's side of the wall.")
		_expect(is_equal_approx((drop.get_node("Visual") as Node3D).scale.x, DROPS.DROP_SCALE), "Drops are half size.")
		for j in range(i + 1, drops.size()):
			var other := drops[j] as Node3D
			var gap := Vector2(drop.global_position.x - other.global_position.x, drop.global_position.z - other.global_position.z).length()
			_expect(gap >= DROPS.DROP_SPACING - 0.01, "Drops do not overlap (%.2f m apart)." % gap)
	for drop in drops:
		drop.queue_free()
	table.queue_free()
	wall.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
