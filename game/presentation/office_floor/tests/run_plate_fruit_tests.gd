extends SceneTree
## Fruit on a plate: seeded random layout, one baked body, config sanitising, and a shot plate
## that breaks on its first hit while its fruit scatters as loose pieces.
const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const PLATE_FRUIT := preload("res://game/presentation/office_floor/plate_fruit.gd")
const PLATE := "res://models/objects/enviroments/09/09_fruit_plate_2.glb"
var failures := 0
var stage: Node3D
var effects: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_config()
	stage = Node3D.new()
	root.add_child(stage)
	effects = Node3D.new()
	stage.add_child(effects)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 3
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(8, 0.2, 8)
	floor_shape.shape = slab
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.1
	await _check_baked_layout()
	for round_index in 5:
		await _shoot_plate(round_index)
	await _check_plain_plate()
	stage.queue_free()
	await process_frame
	print("Plate fruit tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check_config() -> void:
	_check(PLATE_FRUIT.sanitize(null) == {"enabled": false, "count": 3, "seed": 0}, "Missing config is a plate without fruit.")
	_check(PLATE_FRUIT.sanitize({"enabled": true, "count": 99})["count"] == 5, "Count is capped at 5.")
	_check(PLATE_FRUIT.sanitize({"enabled": true, "count": 0})["count"] == 1, "Count is at least 1.")
	_check(PLATE_FRUIT.sanitize({"enabled": "yes"})["enabled"] == false, "Only a real true enables fruit.")
	_check(PLATE_FRUIT.layout(4, 77) == PLATE_FRUIT.layout(4, 77), "The same seed gives the same layout.")
	var variants := {}
	for seed_value in range(1, 40):
		variants[str(PLATE_FRUIT.layout(3, seed_value))] = true
	_check(variants.size() > 10, "Different seeds give different layouts (%d)." % variants.size())
	for count in range(1, 6):
		var items := PLATE_FRUIT.layout(count, 5 + count)
		_check(items.size() == count, "Layout has %d fruits." % count)
		for item: Dictionary in items:
			var at: Vector3 = item["position"]
			_check(Vector2(at.x, at.z).length() <= PLATE_FRUIT.PLATE_RADIUS + 0.001, "Fruit stays on the plate.")


func _make_plate(config: Dictionary, position: Vector3) -> RigidBody3D:
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", PLATE)
	prop.collision_mask = 3
	if not config.is_empty():
		prop.call("configure_fruit", config)
	stage.add_child(prop)
	prop.global_position = position
	prop.call("configure_world", effects, null)
	return prop


func _fruit_meshes(prop: Node) -> int:
	var holder := prop.find_child("Fruit", true, false)
	return 0 if holder == null else holder.find_children("*", "MeshInstance3D", true, false).size()


func _check_baked_layout() -> void:
	for count in range(1, 6):
		var prop := _make_plate({"enabled": true, "count": count, "seed": 100 + count}, Vector3(0, 0.02, 0))
		await physics_frame
		_check(_fruit_meshes(prop) == count, "A plate with %d fruit shows %d fruit meshes." % [count, count])
		_check(prop.call("get_fruit_config")["count"] == count, "Config keeps the count.")
		var live := 0
		for child in prop.get_children():
			if child is CollisionShape3D and not child.disabled:
				live += 1
		_check(live == 1 + count, "Fruit is baked into the plate body: %d shapes for %d fruit." % [live, count])
		prop.call("configure_fruit", {"enabled": false, "count": count})
		_check(_fruit_meshes(prop) == 0, "Switching fruit off removes it live.")
		prop.queue_free()
		await process_frame


func _shoot_plate(round_index: int) -> void:
	var prop := _make_plate({"enabled": true, "count": 1 + round_index % 5, "seed": 500 + round_index}, Vector3(0, 0.02, 0))
	for i in 20:
		await physics_frame
	var pieces_before := effects.get_child_count()
	prop.call("take_projectile_hit", 19.0, prop.global_position + Vector3(0, 0.1, 0), Vector3.UP, Vector3.FORWARD, "PISTOL")
	for i in 40:
		await physics_frame
	var count := 1 + round_index % 5
	_check(effects.get_child_count() - pieces_before >= count, "Round %d: the %d fruit scatter as loose pieces (%d)." % [round_index, count, effects.get_child_count() - pieces_before])
	_check(not (prop.get_node("Visual") as Node3D).visible, "Round %d: the plate breaks on its first hit." % round_index)
	_check(prop.collision_layer == 0, "Round %d: a broken plate stops blocking." % round_index)
	for piece in effects.get_children():
		piece.queue_free()
	prop.queue_free()
	await process_frame


func _check_plain_plate() -> void:
	var prop := _make_plate({}, Vector3(0, 0.02, 0))
	for i in 10:
		await physics_frame
	_check(_fruit_meshes(prop) == 0, "A default plate has no fruit.")
	var before := effects.get_child_count()
	prop.call("take_projectile_hit", 19.0, prop.global_position, Vector3.UP, Vector3.FORWARD, "PISTOL")
	_check(effects.get_child_count() > before, "A plain plate breaks into pieces on a pistol hit.")
	_check(not (prop.get_node("Visual") as Node3D).visible, "A plain plate no longer stands whole.")
	prop.queue_free()


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
