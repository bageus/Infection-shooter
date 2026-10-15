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
	await _test_dna_beacon(stage)
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
		_expect(_matches_placed_size(drop), "Dropped items match the same scene placed directly, including fitted weapon ammo boxes.")
		for j in range(i + 1, drops.size()):
			var other := drops[j] as Node3D
			var gap := Vector2(drop.global_position.x - other.global_position.x, drop.global_position.z - other.global_position.z).length()
			_expect(gap >= DROPS.DROP_SPACING - 0.01, "Drops do not overlap (%.2f m apart)." % gap)
	# The planner instantiates the scene directly; it must match the drop size.
	var placed := (load("res://game/features/pickups/public/medkit_pickup.tscn") as PackedScene).instantiate() as Node3D
	stage.add_child(placed)
	_expect(is_equal_approx((placed.get_node("Visual") as Node3D).scale.x, PICKUP.VISUAL_SCALE), "Placed items use the drop size.")
	placed.queue_free()
	for drop in drops:
		drop.queue_free()
	table.queue_free()
	wall.queue_free()


func _matches_placed_size(drop: Node3D) -> bool:
	var placed := (load(drop.scene_file_path) as PackedScene).instantiate() as Node3D
	drop.get_parent().add_child(placed)
	var same := (placed.get_node("Visual") as Node3D).scale.is_equal_approx((drop.get_node("Visual") as Node3D).scale)
	placed.queue_free()
	return same


# Every DNA gets the rising arrow, whichever way it reaches the level.
func _test_dna_beacon(stage: Node3D) -> void:
	var dna_scene := load("res://game/features/pickups/public/dna_pickup.tscn") as PackedScene
	var from_scene := dna_scene.instantiate() as Node3D
	var from_code := PICKUP.new() as Area3D
	from_code.pickup_type = PICKUP.PickupType.DNA
	var medkit := (load("res://game/features/pickups/public/medkit_pickup.tscn") as PackedScene).instantiate() as Node3D
	var items: Array[Node3D] = [from_scene, from_code, medkit]
	for item in items:
		stage.add_child(item)
		item.position = Vector3(3.0, 1.2, 0.0)
	await physics_frame
	for item in [from_scene, from_code]:
		var beacon := item.get_node_or_null("PickupBeacon") as Node3D
		_expect(beacon != null and beacon.get("_arrow") != null, "A DNA pickup shows its arrow marker.")
	_expect(medkit.get_node_or_null("PickupBeacon") == null, "Other pickups get no DNA arrow.")
	# The arrow floats above the item; the floor must still rest the DNA on the tiles.
	from_scene.call("settle_on_floor")
	await physics_frame
	await physics_frame
	# Measured on the helix alone, not through _visual_bottom_offset, which the marker could also skew.
	var helix_bottom := INF
	for mesh in (from_scene.get_node("Visual") as Node3D).find_children("*", "MeshInstance3D", true, false):
		var part := mesh as MeshInstance3D
		for corner in range(8):
			helix_bottom = minf(helix_bottom, (part.global_transform * part.get_aabb().get_endpoint(corner)).y)
	_expect(is_equal_approx(helix_bottom, 0.018), "A DNA pickup with its arrow still rests on the floor (%.3f)." % helix_bottom)
	for item in items:
		item.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
