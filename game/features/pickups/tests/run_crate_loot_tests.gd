extends SceneTree
## Crate loot hovers above the debris and carries a beacon; drops from enemies stay as they were.
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
	var lift := crate.global_position.y - plain.global_position.y
	_expect(is_equal_approx(lift, LOOT_DROP.CRATE_LIFT), "Crate loot hovers %.2f m above the floor drop (%.2f)." % [LOOT_DROP.CRATE_LIFT, lift])
	_expect(_has_beacon(crate), "Crate loot carries a beacon.")
	_expect(not _has_beacon(plain), "Enemy and placed drops get no crate beacon.")
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
