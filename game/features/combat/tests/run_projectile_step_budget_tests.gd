extends SceneTree
## A02: a bounded ray loop must not move through an unchecked remainder.
const BULLET := preload("res://game/features/combat/public/prototype_bullet.tscn")
const BALANCE := preload("res://game/features/combat/public/projectile_balance.gd")

class Surface:
	extends StaticBody3D
	var hits := 0
	var damages: Array[float] = []
	var material := "glass"
	var stops := false
	func get_projectile_material(_shape: int) -> String:
		return material
	func take_projectile_hit(amount: float, _at: Vector3, _normal: Vector3, _direction: Vector3, _weapon: String) -> bool:
		hits += 1
		damages.append(amount)
		return stops

var failures := 0
var stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for count in [5, 6, 10]:
		for timing: Vector2 in [Vector2(60, 1.0 / 60), Vector2(240, 1.0 / 120), Vector2(12, 1.0 / 120)]:
			await _test_wall(count, timing.x, timing.y, .1)
	# A surface closer than the former .04 m nudge must also block the shot.
	await _test_wall(5, 60.0, 1.0 / 60, .02)
	await _test_range_and_damage()
	await _test_energy_stop()
	await _test_muzzle_origin()
	print("Projectile step budget tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _test_wall(count: int, speed: float, delta: float, wall_gap: float) -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var panels: Array[Surface] = []
	for index in count:
		panels.append(_surface((index + 1) * .1))
	var wall := _surface(count * .1 + wall_gap, true)
	var bullet := _bullet(speed, 4.0)
	await physics_frame
	bullet.call("_physics_process", delta)
	if speed * delta >= 1.0:
		_expect(bullet.position.x <= .5, "Budget exhaustion stays at the last checked hit.")
	for tick in 40:
		if bullet.is_queued_for_deletion():
			break
		var before := wall.hits
		for panel in panels:
			before += panel.hits
		bullet.call("_physics_process", delta)
		var after := wall.hits
		for panel in panels:
			after += panel.hits
		_expect(after - before <= 5, "A tick handles at most five contacts.")
	_expect(wall.hits == 1, "%d panels at %.0f m/s: solid wall receives the shot." % [count, speed])
	_expect(bullet.is_queued_for_deletion() and bullet.position.x < wall.position.x, "The projectile stops on the near face of the wall.")
	for panel in panels:
		_expect(panel.hits == 1, "Each penetrated panel takes damage exactly once.")
	await _clear()


func _test_range_and_damage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var panels: Array[Surface] = []
	for index in 10:
		panels.append(_surface((index + 1) * .1))
	var beyond_range := _surface(1.4, true)
	var bullet := _bullet(120.0, 1.25)
	await physics_frame
	bullet.call("_physics_process", 1.0 / 60)
	_expect(bullet.position.x < .5, "First budget cannot consume the full range.")
	# Change delta during continuation: the original end and distance must persist.
	bullet.call("_physics_process", .001)
	_expect(bullet.position.x < 1.0, "Second budget still stops at its last checked hit.")
	bullet.call("_physics_process", .001)
	_expect(is_equal_approx(bullet.position.x, 1.25), "Completing a pending segment reaches its original end.")
	_expect(is_equal_approx(float(bullet.get("_travelled")), 1.25), "Deferred distance is accounted exactly once.")
	bullet.call("_physics_process", 1.0 / 60)
	_expect(bullet.is_queued_for_deletion() and beyond_range.hits == 0, "Range expiry never hits a target beyond range.")
	var energy := BALANCE.projectile_energy("SNIPER RIFLE")
	for panel in panels:
		_expect(panel.hits == 1, "Continuation retains exclusions across three budgets.")
		if panel.hits == 1:
			_expect(is_equal_approx(panel.damages[0], 100.0 * energy / 110.0), "Damage retains the correct energy across continuation.")
		energy -= BALANCE.material_cost("glass")
	await _clear()


func _test_energy_stop() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var panels: Array[Surface] = []
	for index in 16:
		panels.append(_surface((index + 1) * .1))
	var bullet := _bullet(240.0, 4.0)
	await physics_frame
	for tick in 5:
		if bullet.is_queued_for_deletion():
			break
		bullet.call("_physics_process", 1.0 / 60)
	_expect(bullet.is_queued_for_deletion(), "Energy still terminates a continued shot.")
	for index in panels.size():
		_expect(panels[index].hits == (1 if index < 13 else 0), "Energy exhaustion prevents later hits without repeating prior ones.")
	await _clear()


func _test_muzzle_origin() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var shooter := _surface(0.0)
	var wall := _surface(.15, true)
	var bullet := _bullet(60, 4.0, shooter, .3, Vector3(0, 1, 0))
	await physics_frame
	bullet.call("_physics_process", 1.0 / 60)
	_expect(shooter.hits == 0 and wall.hits == 1, "Muzzle trace excludes the shooter and catches a wall behind the barrel.")
	_expect(bullet.is_queued_for_deletion(), "Muzzle obstruction still terminates the shot.")
	var inside := _bullet(60, 4.0, shooter, .3, wall.position)
	inside.call("_physics_process", 1.0 / 60)
	_expect(wall.hits == 2 and inside.is_queued_for_deletion(), "An origin inside the wall is still blocked on the first ray.")
	await _clear()


func _surface(x: float, stops: bool = false) -> Surface:
	var body := Surface.new()
	body.position = Vector3(x, 1, 0)
	body.stops = stops
	body.material = "concrete" if stops else "glass"
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(.01, 2, 2)
	body.add_child(collision)
	stage.add_child(body)
	return body


func _bullet(speed: float, max_range: float, shooter: CollisionObject3D = null, spawn_x: float = 0.0, origin: Vector3 = Vector3.ZERO) -> Node3D:
	var bullet := BULLET.instantiate() as Node3D
	stage.add_child(bullet)
	bullet.position = Vector3(spawn_x, 1, 0)
	bullet.call("setup_projectile", Vector3.RIGHT, shooter, 100.0, speed, max_range, "SNIPER RIFLE", origin)
	bullet.set_physics_process(false)
	return bullet


func _clear() -> void:
	stage.queue_free()
	await process_frame
	await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
