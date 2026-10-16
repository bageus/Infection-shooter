extends SceneTree
const ENEMY := preload("res://game/features/infected/public/infected_capsule.tscn")
const BULLET := preload("res://game/features/combat/public/prototype_bullet.tscn")
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const EFFECTS := preload("res://game/presentation/office_floor/public/blood_effects_3d.tscn")

class Receiver:
	extends StaticBody3D
	var penetrable := false
	func get_projectile_material(_shape: int) -> String:
		return "wood" if penetrable else "solid"
	func take_projectile_hit(_d: float, _p: Vector3, _n: Vector3, _v: Vector3, _w: String) -> bool:
		return not penetrable

var failures := 0
var stage: Node3D
var effects: Node3D
var impacts: Node3D
var floor_body: StaticBody3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	floor_body = _surface(Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	impacts = IMPACTS.new()
	stage.add_child(impacts)
	effects = EFFECTS.instantiate()
	stage.add_child(effects)
	effects.call("configure_world", stage, impacts)
	var roots: Array[Node] = [floor_body]
	effects.call("configure_environment", roots)
	impacts.connect("penetration_blood", Callable(effects, "splatter_exit"))
	await _exit_on_surface(false)
	await _exit_on_surface(true)
	await _no_surface()
	await _landed_pool()
	stage.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	print("Exit blood surface integration tests: %d failures" % failures)
	quit(1 if failures else 0)


func _surface(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := Receiver.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	body.add_child(visual)
	stage.add_child(body)
	return body


func _enemy(point: Vector3) -> Node3D:
	var enemy := ENEMY.instantiate() as Node3D
	stage.add_child(enemy)
	enemy.position = point
	enemy.set_physics_process(false)
	enemy.call("configure_world", stage, impacts)
	return enemy


func _marks() -> Array[Node]:
	return effects.get("_budget").get("container").get_children()


func _exit_on_surface(moving: bool) -> void:
	effects.call("clear_marks")
	var enemy := _enemy(Vector3(2, 1, 0))
	enemy.set("health", 500.0)
	var receiver := _surface(Vector3(3.2, 1.5, 0), Vector3(0.2, 3, 3))
	receiver.set("penetrable", moving)
	var roots: Array[Node] = [receiver]
	effects.call("configure_environment", roots)
	var bullet := BULLET.instantiate() as Node3D
	stage.add_child(bullet)
	bullet.position = Vector3(0, 1, 0)
	bullet.call("configure_world", stage, impacts)
	bullet.call("setup_projectile", Vector3.RIGHT, null, 20.0, 360.0, 10.0, "SNIPER RIFLE")
	bullet.set_physics_process(false)
	await physics_frame
	await physics_frame
	for i in 2:
		if is_instance_valid(bullet) and not bullet.is_queued_for_deletion():
			bullet.call("_physics_process", 1.0 / 60)
	await physics_frame
	await physics_frame
	var marks := _marks()
	_expect(not marks.is_empty(), "Confirmed flesh exit stamps the first wall/partition/furniture surface behind the body")
	for mark in marks:
		_expect(mark.get("surface_ref").get_ref() == receiver, "Every cone stamp belongs to the actual receiving object")
	if moving and not marks.is_empty():
		var mark := marks[0] as Node3D
		var local_point := receiver.to_local(mark.global_position)
		receiver.position.z += 0.7
		await physics_frame
		await physics_frame
		_expect(receiver.to_local(mark.global_position).distance_to(local_point) < 0.001, "Blood moves with its receiving furniture")
	enemy.queue_free()
	receiver.queue_free()
	if is_instance_valid(bullet):
		bullet.queue_free()
	await process_frame


func _no_surface() -> void:
	effects.call("clear_marks")
	var excluded: Array[RID] = []
	effects.call("splatter_exit", Vector3(100, 1, 100), Vector3.RIGHT, 78.0, excluded)
	await physics_frame
	await physics_frame
	_expect(_marks().is_empty(), "An absent receiving surface cannot create floating blood")


func _landed_pool() -> void:
	effects.call("clear_marks")
	var enemy := _enemy(Vector3(-3, 1, -3))
	enemy.connect("blood_pool_ready", Callable(effects, "death_pool"))
	var landed_points: Array[Vector3] = []
	enemy.connect("blood_pool_ready", func(p: Vector3, _r: Array[RID], _id: int) -> void: landed_points.append(p))
	# Match bootstrap: death fact remains immediate; only the landed fact schedules this pool.
	var immediate := [0]
	enemy.connect("blood_death", func(_p: Vector3, _r: Array[RID], _id: int) -> void: immediate[0] += 1)
	enemy.call("take_damage", 1000.0)
	_expect(immediate[0] == 1 and _marks().is_empty(), "Death semantics remain immediate while the pool waits for the fall")
	await create_timer(2.7).timeout
	var marks := _marks()
	_expect(marks.size() == 1, "A fallen real enemy produces exactly one growing pool")
	if not marks.is_empty():
		var mark := marks[0] as Node3D
		_expect(mark.get("surface_ref").get_ref() == floor_body and absf(mark.global_position.y) < 0.03, "The corpse pool is on the floor beneath the actual body")
		_expect(landed_points.size() == 1, "One settled-body position feeds the renderer")
		if not landed_points.is_empty():
			var delta := mark.global_position - landed_points[0]
			_expect(Vector2(delta.x, delta.z).length() < 0.05, "Pool is directly under the reported torso, not at the predicted death location")
		var records: Dictionary = effects.get("_budget").get("_records")
		for record in records.values():
			var size: Vector2 = record.definition.footprint
			_expect(maxf(size.x, size.y) >= 1.5, "The pool extends around the fallen body")
	enemy.queue_free()
	await process_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
