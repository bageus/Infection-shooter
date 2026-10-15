extends SceneTree
## A03: ignored furniture must not hide a structural wall from the blast ray.
const BLAST := preload("res://game/features/combat/public/grenade_explosion.gd")
const DOORWAY := preload("res://game/presentation/office_floor/public/structural/wall_door_3_without.tscn")

class Recipient extends StaticBody3D:
	var damage := 0.0
	func take_damage(amount: float) -> void:
		damage += amount

class Damageable extends StaticBody3D:
	func take_projectile_hit(_damage: float, _at: Vector3, _normal: Vector3, _direction: Vector3, _weapon: String) -> bool:
		return false

var failures := 0
var stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for count in [0, 6, 10, 64]:
		for side in [-1.0, 1.0]:
			for kind in ["rigid", "damageable", "own_parts"]:
				await _test_chain(count, side, kind, true)
				await _test_chain(count, side, kind, false)
	await _test_mount_clearance()
	await _test_damageable_wall()
	await _test_real_doorway()
	await _test_damage_dispatch()
	print("Blast shelter tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _start() -> void:
	stage = Node3D.new()
	root.add_child(stage)


func _test_chain(count: int, side: float, kind: String, with_wall: bool) -> void:
	_start()
	var target := Recipient.new()
	_box(target, Vector3(-side * 2, .5, 0), Vector3.ONE * .1)
	if with_wall:
		_box(StaticBody3D.new(), Vector3(0, 1, 0), Vector3(.1, 3, 3))
	for index in count:
		var at := Vector3(side * lerpf(1.8, .2, float(index) / maxi(1, count - 1)), 1, 0)
		var body: CollisionObject3D
		if kind == "rigid":
			var prop := RigidBody3D.new()
			prop.freeze = index % 2 == 0
			prop.gravity_scale = 0.0
			body = prop
		elif kind == "damageable":
			body = Damageable.new()
		else:
			body = StaticBody3D.new()
		_box(body, at, Vector3(.01, 1, 1), target if kind == "own_parts" else stage)
	await physics_frame
	await physics_frame
	var sheltered := BLAST.is_sheltered(stage.get_world_3d(), Vector3(side * 2, 1, 0), target)
	_expect(sheltered == with_wall, "%s/%d/side %.0f: only a real wall shelters, present=%s." % [kind, count, side, with_wall])
	await _clear()


func _test_mount_clearance() -> void:
	for side in [-1.0, 1.0]:
		_start()
		_box(StaticBody3D.new(), Vector3(0, 1, 0), Vector3(.1, 3, 3))
		var mounted := Recipient.new()
		_box(mounted, Vector3(-side * .1, .5, 0), Vector3.ONE * .1)
		await physics_frame
		await physics_frame
		_expect(not BLAST.is_sheltered(stage.get_world_3d(), Vector3(side * 2, 1, 0), mounted), "A wall within mount clearance does not shelter its mounted item.")
		await _clear()


func _test_damageable_wall() -> void:
	_start()
	_box(Damageable.new(), Vector3(0, 1, 0), Vector3(.1, 3, 3))
	var target := Recipient.new()
	_box(target, Vector3(2, .5, 0), Vector3.ONE * .1)
	await physics_frame
	await physics_frame
	_expect(not BLAST.is_sheltered(stage.get_world_3d(), Vector3(-2, 1, 0), target), "Damageable walls keep their existing non-sheltering rule.")
	await _clear()


func _test_real_doorway() -> void:
	_start()
	var doorway := DOORWAY.instantiate() as Node3D
	stage.add_child(doorway)
	for side in [-1.0, 1.0]:
		var target := Recipient.new()
		_box(target, Vector3(0, .5, -side * 2), Vector3.ONE * .1)
		var props: Array[RigidBody3D] = []
		for index in 10:
			var prop := RigidBody3D.new()
			prop.freeze = true
			_box(prop, Vector3(0, 1, side * lerpf(1.8, .3, float(index) / 9)), Vector3(.1, 1, .01))
			props.append(prop)
		await process_frame
		await physics_frame
		await physics_frame
		_expect(doorway.get_node("Body").get_child_count() > 0, "The authored door frame has actual mesh collisions.")
		_expect(not BLAST.is_sheltered(stage.get_world_3d(), Vector3(0, 1, side * 2), target), "The authored doorway stays open behind ten props.")
		target.position.x = .95
		for prop in props:
			prop.position.x = .95
		await physics_frame
		await physics_frame
		_expect(BLAST.is_sheltered(stage.get_world_3d(), Vector3(.95, 1, side * 2), target), "The same door frame's jamb shelters behind ten props.")
		target.queue_free()
		for prop in props:
			prop.queue_free()
		await process_frame
	await _clear()


func _test_damage_dispatch() -> void:
	_start()
	var hidden := Recipient.new()
	_box(hidden, Vector3(2, .5, 0), Vector3.ONE * .1)
	var exposed := Recipient.new()
	_box(exposed, Vector3(-2, .5, 2), Vector3.ONE * .1)
	_box(StaticBody3D.new(), Vector3(0, 1, 0), Vector3(.1, 3, 3))
	for index in 10:
		var prop := RigidBody3D.new()
		prop.freeze = true
		_box(prop, Vector3(lerpf(-1.8, -.2, float(index) / 9), 1, 0), Vector3(.01, 2, 1))
	await physics_frame
	await physics_frame
	var anchor := Node3D.new()
	stage.add_child(anchor)
	BLAST.explode(anchor, Vector3(-2, 1, 0), Vector3.UP, null, stage, null)
	_expect(hidden.damage == 0.0, "Real explosion dispatch does not damage a target behind the wall and furniture.")
	_expect(exposed.damage > 0.0, "The same explosion still damages an exposed target.")
	await _clear()


func _box(body: CollisionObject3D, at: Vector3, size: Vector3, parent: Node3D = null) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = size
	body.add_child(collision)
	(stage if parent == null else parent).add_child(body)
	body.global_position = at


func _clear() -> void:
	stage.queue_free()
	await process_frame
	await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
