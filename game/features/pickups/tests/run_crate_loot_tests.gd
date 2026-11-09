extends SceneTree
## Crate loot carries a beacon and sits on the floor; drops from enemies stay as they were.
const LOOT_DROP := preload("res://game/features/pickups/public/loot_drop.gd")
const DROP_TABLE := preload("res://game/features/pickups/public/drop_table.gd")
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
	box.size = Vector3(40, 0.2, 40)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.1
	await physics_frame
	# Same spot on the floor, far apart so free_spot never moves either drop.
	LOOT_DROP.spawn(stage, ["medkit"], Vector3(-10, 0, 0), Callable())
	LOOT_DROP.spawn(stage, ["medkit"], Vector3(10, 0, 0), Callable(), true)
	await physics_frame
	await physics_frame
	await process_frame
	var plain: Node3D = null
	var crate: Node3D = null
	for node in get_nodes_in_group(DROP_TABLE.DROP_GROUP):
		var item := node as Node3D
		if item == null:
			continue
		if item.global_position.x < 0.0:
			plain = item
		else:
			crate = item
	_expect(plain != null and crate != null, "Both drops spawn.")
	if plain == null or crate == null:
		return _finish()
	_expect(is_equal_approx(crate.global_position.y, plain.global_position.y), "Crate loot rests on the floor like other drops.")
	_expect(_has_beacon(crate), "Crate loot carries a beacon.")
	_expect(not _has_beacon(plain), "Enemy and placed drops get no crate beacon.")
	var beacon_script := load("res://game/features/pickups/public/pickup_beacon.gd")
	var arrow_beacon: Node3D = beacon_script.make(Color.GREEN, 1.0, 1.0)
	var no_arrow_beacon: Node3D = beacon_script.make(Color.GREEN, 1.0, 0.0)
	_expect(arrow_beacon.get("_arrow") != null and arrow_beacon.get("_arrow").material_override is ShaderMaterial, "Beacon arrow is shader-drawn.")
	_expect(no_arrow_beacon.get("_arrow") == null, "Beacon without arrow height has no arrow.")
	arrow_beacon.free()
	no_arrow_beacon.free()
	for drop in [plain, crate]:
		drop.queue_free()
	stage.queue_free()
	_finish()


func _has_beacon(item: Node) -> bool:
	for child in item.get_children():
		if child.name == "PickupBeacon":
			return true
	return false


func _finish() -> void:
	print("Crate loot tests: %d failure(s)." % failures)
	quit(failures)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
