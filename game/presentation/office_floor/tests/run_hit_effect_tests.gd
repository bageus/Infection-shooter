extends SceneTree
## Runtime checks for hit effects on props: paper is torn apart by one shot,
## electronics short-circuit (spark sheet + flash) on the first hit only, and a
## shot fire extinguisher sprays, drops on its side and ruptures with sound.

const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
const MODELS := "res://models/objects/enviroments/"

var failures := 0
var stage: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	_add_floor()
	await _test_paper()
	await _test_short_circuit()
	await _test_extinguisher()
	stage.queue_free()
	await process_frame
	print("Hit effect tests: %d failure(s)." % failures)
	quit(failures)


func _test_paper() -> void:
	for model in ["09/09_paper_stack.glb", "09/09_notepad.glb", "09/09_office_files_a.glb"]:
		var setup := await _spawn(MODELS + model, Vector3(0, 0.0, 0))
		var prop: RigidBody3D = setup[0]
		var effects: Node3D = setup[1]
		prop.call("take_projectile_hit", 5.0, prop.global_position + Vector3(0, 0.05, 0), Vector3.UP, Vector3.FORWARD, "PISTOL")
		await process_frame
		await process_frame
		_expect(not is_instance_valid(prop), "One shot destroys paper completely: " + model)
		var scraps := effects.find_children("Flipbook*", "", false, false).size()
		if ATLASES.available(ATLASES.TORN_PAPER):
			_expect(scraps >= 5 and scraps <= 6, "Torn paper bursts into 5-6 sheet scraps (%d): %s" % [scraps, model])
		else:
			_expect(effects.get_node_or_null("TornPaper") != null, "Torn paper falls back to shreds: " + model)
		effects.queue_free()
		await process_frame


func _test_short_circuit() -> void:
	var setup := await _spawn(MODELS + "05/05_PC_destructible.glb", Vector3(4, 0, 0))
	var prop: RigidBody3D = setup[0]
	var effects: Node3D = setup[1]
	var point := prop.global_position + Vector3(0, 0.4, 0)
	prop.call("take_projectile_hit", 1.0, point, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	await process_frame
	_expect(effects.get_node_or_null("SparkFlash") != null, "The first hit on a device flashes a short circuit.")
	if ATLASES.available(ATLASES.ELECTRIC_SPARK):
		var bursts := prop.find_children("Flipbook*", "", false, false)
		_expect(not bursts.is_empty() and (bursts[0] as Node3D).global_position.distance_to(point) < 0.3, "The spark sheet plays next to the hit.")
		await create_timer(1.0).timeout
		_expect(prop.find_children("Flipbook*", "", false, false).is_empty(), "Sparking stops after a moment.")
	await create_timer(0.2).timeout
	prop.call("take_projectile_hit", 1.0, point, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	await process_frame
	_expect(effects.get_node_or_null("SparkFlash") == null, "Later hits only throw small sparks.")
	prop.queue_free()
	effects.queue_free()
	await process_frame


func _test_extinguisher() -> void:
	var setup := await _spawn(MODELS + "09/09_fire_extinguisher.glb", Vector3(-4, 0, 0))
	var prop: RigidBody3D = setup[0]
	var effects: Node3D = setup[1]
	prop.call("take_projectile_hit", 10.0, prop.global_position + Vector3(0, 0.3, 0), Vector3.BACK, Vector3.FORWARD, "PISTOL")
	_expect(await _heard(&"extinguisher_spray", 0.5), "A shot extinguisher hisses as it sprays.")
	_expect(await _heard(&"canister_drop", 3.0), "The toppled cylinder clangs on the floor.")
	_expect(await _heard(&"extinguisher_burst", 4.5), "The extinguisher ruptures with a burst.")
	await create_timer(0.2).timeout
	_expect(_voices(&"extinguisher_spray") == 0, "The spray sound stops when it ruptures.")
	if is_instance_valid(prop):
		prop.queue_free()
	effects.queue_free()
	await process_frame


func _spawn(path: String, position: Vector3) -> Array:
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", path)
	prop.collision_mask = 3
	stage.add_child(prop)
	prop.global_position = position
	prop.call("configure_world", effects, null)
	await physics_frame
	await physics_frame
	return [prop, effects]


func _voices(event: StringName) -> int:
	return get_nodes_in_group(StringName("sfx_" + str(event))).size()


func _heard(event: StringName, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if _voices(event) > 0:
			return true
		await process_frame
	return _voices(event) > 0


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
