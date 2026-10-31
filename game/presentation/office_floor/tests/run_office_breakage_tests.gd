extends SceneTree
## Runtime checks for office breakage: cardboard bursts apart, a monitor
## shows its Power_Off stage when shorted, a wood partition drops the VECTRION
## logo, and a wood slat partition rings like wood.

const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MODELS := "res://models/objects/enviroments/"
const CARDBOARD := MODELS + "04/04_cardboard_boxes_1.glb"
const MONITOR := MODELS + "05/05_monitor_destructible.glb"
const PARTITION := MODELS + "01/01_wood_slat_partition_destructible.glb"
const LOGO := MODELS + "01/01_VECTRION_Destructible.glb"
const WOOD_CRATE := MODELS + "02/02_crate_wood_large.glb"

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	_add_floor(stage)
	await _test_cardboard(stage)
	await _test_monitor_power_off(stage)
	await _test_partition_logo(stage)
	await _test_partition_sound()
	await _test_crate_strike(stage)
	await _test_crate_walls(stage)
	await _test_pallet_scatter(stage)
	print("%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _test_cardboard(stage: Node3D) -> void:
	var setup := await _spawn(stage, CARDBOARD, Vector3(0, 0, 0))
	var box: RigidBody3D = setup[0]
	var visual := box.get_node("Visual") as Node3D
	var shots := 0
	for i in 12:
		if not is_instance_valid(box) or not visual.visible:
			break
		box.call("take_projectile_hit", 32.0, box.global_position + Vector3(0, 0.3, 0), Vector3.UP, Vector3.FORWARD, "SHOTGUN")
		shots += 1
		await process_frame
	_expect(not visual.visible, "A cardboard box bursts apart from shotgun hits.")
	_expect(shots <= 8, "A cardboard box breaks in as few shotgun pellets as a wooden crate.")
	_expect(setup[1].get_child_count() > 0, "A broken cardboard box leaves its panels as pieces.")
	await _clear(box, setup[1])


func _test_crate_strike(stage: Node3D) -> void:
	var setup := await _spawn(stage, WOOD_CRATE, Vector3(-10, 0, 0))
	var crate: RigidBody3D = setup[0]
	var visual := crate.get_node("Visual") as Node3D
	_expect(crate.call("has_loot"), "A wooden crate is a loot crate.")
	crate.call("break_by_strike", crate.global_position + Vector3(0, 0.3, 0), Vector3.FORWARD)
	await process_frame
	_expect(not visual.visible and crate.freeze, "A kick or heavy punch breaks a loot crate in one blow, stages or not.")
	await _clear(crate, setup[1])


func _test_crate_walls(stage: Node3D) -> void:
	var setup := await _spawn(stage, WOOD_CRATE, Vector3(-10, 0.0135, -6))
	var crate: RigidBody3D = setup[0]
	crate.call("break_by_strike", crate.global_position + Vector3(0.3, 0.3, 0), Vector3.FORWARD)
	await physics_frame
	var walls: Array[RigidBody3D] = []
	for child in setup[1].get_children():
		if child is RigidBody3D:
			walls.append(child)
	_expect(walls.size() >= 4, "A big wooden crate breaks into its walls, not one piece (%d)." % walls.size())
	for frame in 240:
		await physics_frame
	var flat := true
	for wall in walls:
		flat = flat and is_instance_valid(wall) and wall.global_position.y < 0.5
	_expect(flat, "The walls of a broken crate fall down and lie on the floor.")
	await _clear(crate, setup[1])


func _test_pallet_scatter(stage: Node3D) -> void:
	var setup := await _spawn(stage, MODELS + "02/02_pallet.glb", Vector3(-10, 0.0135, 6))
	var pallet: RigidBody3D = setup[0]
	for i in 14:
		if is_instance_valid(pallet) and not bool(pallet.get("_broken")):
			pallet.call("take_projectile_hit", 60.0, pallet.global_position + Vector3(0.3, 0.1, 0), Vector3.UP, Vector3.FORWARD, "SHOTGUN")
			await physics_frame
	for frame in 90:
		await physics_frame
	var farthest := 0.0
	for child in setup[1].get_children():
		if child is RigidBody3D:
			farthest = maxf(farthest, Vector2(child.global_position.x + 10.0, child.global_position.z - 6.0).length())
	_expect(farthest > 0.9, "A broken pallet falls apart: boards and blocks spread out (%.2f m)." % farthest)
	await _clear(pallet, setup[1])


func _test_monitor_power_off(stage: Node3D) -> void:
	var setup := await _spawn(stage, MONITOR, Vector3(-5, 0, 0))
	var monitor: RigidBody3D = setup[0]
	var power_off := monitor.get_node("Visual").get_node_or_null("Power_Off") as Node3D
	monitor.call("take_projectile_hit", 19.0, monitor.global_position + Vector3(0, 0.8, 0), Vector3.BACK, Vector3.FORWARD, "PISTOL")
	await process_frame
	_expect(power_off != null and power_off.visible and power_off.scale == Vector3.ONE, "A shorted monitor shows its Power_Off stage.")
	_expect(not (monitor.get("_intact") as Node3D).visible, "A shorted monitor hides its powered screen.")
	await _clear(monitor, setup[1])


func _test_partition_logo(stage: Node3D) -> void:
	var partition_setup := await _spawn(stage, PARTITION, Vector3(-10, 0, 5))
	var partition: RigidBody3D = partition_setup[0]
	var logo_setup := await _spawn(stage, LOGO, Vector3(-10, 1.5, 5.05))
	var logo: RigidBody3D = logo_setup[0]
	await process_frame
	_expect(logo.freeze, "The VECTRION logo starts mounted on the partition.")
	for i in 12:
		if not is_instance_valid(partition) or bool(partition.get("_broken")):
			break
		partition.call("take_projectile_hit", 400.0, partition.global_position + Vector3(0, 0.5, 0), Vector3.UP, Vector3.FORWARD, "GRENADE")
		await create_timer(0.1).timeout
	await create_timer(0.3).timeout
	_expect(not is_instance_valid(logo) or not logo.freeze, "The VECTRION logo falls when its partition breaks.")
	await _clear(partition, partition_setup[1])
	await _clear(logo, logo_setup[1])


func _test_partition_sound() -> void:
	var partition := PROP_SCENE.instantiate() as RigidBody3D
	partition.set("model_path", PARTITION)
	_expect(partition.call("get_projectile_material", -1) == "concrete", "Wood slat partitions keep their bullet cost as concrete.")
	_expect(partition.call("get_impact_sound_material", -1) == "wood", "Wood slat partitions ring like wood on impact.")
	partition.free()
	for model in ["03/03_bookshelf.glb", "03/03_book_case_small.glb", "03/03_book_case_with_back.glb", "03/03_file_cabinet_largest.glb", "03/03_file_cabinet_smaller.glb", "03/03_file_cabinet_small_shelf_fancy.glb", "03/03_file_cabinet_large_shelf_fancy.glb"]:
		var furniture := PROP_SCENE.instantiate() as RigidBody3D
		furniture.set("model_path", MODELS + model)
		_expect(furniture.call("get_impact_sound_material", -1) == "wood", "%s rings like wood on impact." % model.get_file())
		furniture.free()
	var locker := PROP_SCENE.instantiate() as RigidBody3D
	locker.set("model_path", MODELS + "03/03_locker_tall_dented.glb")
	_expect(locker.call("get_impact_sound_material", -1) == "metal", "Metal lockers still ring like metal on impact.")
	locker.free()


func _spawn(stage: Node3D, path: String, position: Vector3) -> Array:
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", path)
	prop.collision_mask = 3
	stage.add_child(prop)
	prop.global_position = position
	prop.call("configure_world", effects, null)
	await physics_frame
	return [prop, effects]


func _clear(prop: Node, effects: Node) -> void:
	if is_instance_valid(prop):
		prop.queue_free()
	effects.queue_free()
	await process_frame


func _add_floor(stage: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.0865 # Top at the real floor height (FLOOR_TOP).


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
