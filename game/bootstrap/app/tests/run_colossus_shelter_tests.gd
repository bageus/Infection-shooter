extends SceneTree
## N02: a real Colossus wave must see the wall beyond ignored furniture.
const COLOSSUS := preload("res://game/features/infected/public/infected_colossus.tscn")
const DOORWAY := preload("res://game/presentation/office_floor/public/structural/wall_door_3_without.tscn")
const PLAYER := preload("res://game/features/player/public/player.tscn")

class Recipient extends CharacterBody3D:
	var damage := 0.0
	var hits := 0
	func take_damage(amount: float) -> void:
		damage += amount
		hits += 1

class Prop extends RigidBody3D:
	var damage := 0.0
	var hits := 0
	func take_projectile_hit(_damage: float, _at: Vector3, _normal: Vector3, _direction: Vector3, _weapon: String) -> bool:
		damage += _damage
		hits += 1
		return false

var failures := 0
var stage: Node3D
var source: Node3D
var effects: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for count in [0, 1, 8, 16, 64]:
		for side in [-1.0, 1.0]:
			await _chain(count, side, true)
			await _chain(count, side, false)
	await _own_parts()
	await _static_cover()
	await _doorway()
	await _dispatch()
	await _real_player()
	# Give the audio server time to release voices freed with their scene.
	await create_timer(0.1).timeout
	print("Colossus shelter tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _start() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	effects = Node3D.new()
	stage.add_child(effects)
	source = COLOSSUS.instantiate() as Node3D
	stage.add_child(source)
	source.set_process(false)
	source.set_physics_process(false)
	source.call("configure_world", effects, null)


func _wave(origin := Vector3.ZERO) -> Node3D:
	# _release_slam computes feet at -0.9 local Z and half a capsule below root.
	var capsule := (source.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	source.position = origin + Vector3(0, capsule.height * .5, .9)
	source.call("_release_slam")
	var wave := effects.get_node("SlamWave") as Node3D
	wave.set_physics_process(false)
	_check(wave.global_position.is_equal_approx(origin), "Real Colossus releases the wave at the expected feet position")
	return wave


func _chain(count: int, side: float, with_wall: bool) -> void:
	_start()
	var target := Recipient.new()
	_box(target, Vector3(side * 3, .5, 0), Vector3.ONE * .1)
	if with_wall:
		_box(StaticBody3D.new(), Vector3(side * 2, 1, 0), Vector3(.1, 3, 3))
	for index in count:
		var prop := RigidBody3D.new()
		prop.freeze = index % 2 == 0
		prop.gravity_scale = 0.0
		_box(prop, Vector3(side * lerpf(.15, 1.8, float(index) / maxi(1, count - 1)), .7, 0), Vector3(.01, 1.4, .2))
	var wave := _wave()
	await _sync()
	_check(bool(wave.call("_sheltered", target)) == with_wall, "%d frozen/dynamic props, side %.0f, wall=%s: cover depends on the wall" % [count, side, with_wall])
	await _clear()


func _own_parts() -> void:
	for owner_kind in ["source", "target"]:
		for with_wall in [false, true]:
			_start()
			var target := Recipient.new()
			_box(target, Vector3(3, .5, 0), Vector3.ONE * .1)
			var part_owner := source if owner_kind == "source" else target
			var part := StaticBody3D.new()
			_box(part, Vector3(.8, .6, 0), Vector3(.1, 1.2, .2), part_owner)
			if with_wall:
				_box(StaticBody3D.new(), Vector3(2, 1, 0), Vector3(.1, 3, 3))
			var wave := _wave()
			# Source moves to put its feet at origin; keep the synthetic bone on the ray.
			part.global_position = Vector3(.8, .6, 0)
			await _sync()
			_check(bool(wave.call("_sheltered", target)) == with_wall, "%s hitbox is not cover and does not hide the next wall" % owner_kind)
			await _clear()


func _static_cover() -> void:
	_start()
	var target := Recipient.new()
	_box(target, Vector3(3, .5, 0), Vector3.ONE * .1)
	var wall := StaticBody3D.new()
	_box(wall, Vector3(2, 1, 0), Vector3(.1, 3, 3))
	var wave := _wave()
	await _sync()
	_check(bool(wave.call("_sheltered", target)), "Static cover keeps the previous blocking rule")
	wall.collision_layer = 0
	await _sync()
	_check(not bool(wave.call("_sheltered", target)), "A disabled/destroyed wall no longer shelters")
	await _clear()


func _doorway() -> void:
	for side in [-1.0, 1.0]:
		_start()
		var frame := DOORWAY.instantiate() as Node3D
		stage.add_child(frame)
		var target := Recipient.new()
		_box(target, Vector3(0, .5, -side * 2), Vector3.ONE * .1)
		var props: Array[RigidBody3D] = []
		for index in 10:
			var prop := RigidBody3D.new()
			prop.freeze = true
			_box(prop, Vector3(0, .6, side * lerpf(1.8, .3, float(index) / 9)), Vector3(.1, 1.2, .01))
			props.append(prop)
		var wave := _wave(Vector3(0, 0, side * 2))
		await _sync()
		_check(frame.get_node("Body").get_child_count() > 0, "Authored doorway has actual collision shapes")
		_check(not bool(wave.call("_sheltered", target)), "Wave passes through the authored doorway behind furniture")
		target.position.x = .95
		wave.position.x = .95
		for prop in props:
			prop.position.x = .95
		await _sync()
		_check(bool(wave.call("_sheltered", target)), "Authored jamb still shelters behind furniture")
		await _clear()


func _dispatch() -> void:
	_start()
	var hidden := Recipient.new()
	hidden.add_to_group("player")
	_box(hidden, Vector3(3, .5, 0), Vector3.ONE * .2)
	var exposed := Recipient.new()
	exposed.add_to_group("player")
	_box(exposed, Vector3(-3, .5, 0), Vector3.ONE * .2)
	var protected_prop := Prop.new()
	protected_prop.freeze = true
	_box(protected_prop, Vector3(3, .5, 1), Vector3.ONE * .2)
	var loose := Prop.new()
	loose.gravity_scale = 0.0
	_box(loose, Vector3(-3, .5, 1), Vector3.ONE * .2)
	_box(StaticBody3D.new(), Vector3(2, 1, 0), Vector3(.1, 3, 4))
	for index in 10:
		var prop := RigidBody3D.new()
		prop.freeze = true
		_box(prop, Vector3(lerpf(.2, 1.8, float(index) / 9), .6, 0), Vector3(.01, 1.2, 3))
	var wave := _wave()
	await _sync()
	wave.set("_radius", 4.0)
	wave.call("_strike_passed_bodies")
	wave.call("_strike_passed_bodies")
	_check(hidden.hits == 0, "Dispatch never damages the player behind the wall and furniture")
	_check(protected_prop.hits == 0, "Dispatch protects breakable furniture behind the same wall")
	_check(exposed.hits == 1 and exposed.damage > 0.0, "Exposed player is hit once, never once per query")
	_check(loose.hits == 1 and loose.damage > 0.0, "Exposed breakable furniture is hit once")
	await _sync()
	_check(loose.linear_velocity.length() > 0.0, "Exposed loose furniture still receives its impulse")
	await _clear()


func _real_player() -> void:
	for with_wall in [true, false]:
		_start()
		var player := PLAYER.instantiate() as CharacterBody3D
		stage.add_child(player)
		player.set_process(false)
		player.set_physics_process(false)
		player.position = Vector3(3, 1, 0)
		player.set("armor", 0.0)
		var health := float(player.get("health"))
		if with_wall:
			_box(StaticBody3D.new(), Vector3(2, 1, 0), Vector3(.1, 3, 3))
		var prop := RigidBody3D.new()
		prop.freeze = true
		_box(prop, Vector3(1, .7, 0), Vector3(.1, 1.4, .2))
		var wave := _wave()
		await _sync()
		wave.set("_radius", 4.0)
		_check(bool(wave.call("_sheltered", player)) == with_wall, "Real Player cover query agrees with wall=%s" % with_wall)
		wave.call("_strike_passed_bodies")
		_check(is_equal_approx(float(player.get("health")), health) == with_wall, "Real Player health protected only by wall=%s, health %.2f -> %.2f" % [with_wall, health, float(player.get("health"))])
		await _clear()


func _box(body: CollisionObject3D, at: Vector3, size: Vector3, parent: Node3D = null) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	(collision.shape as BoxShape3D).size = size
	body.add_child(collision)
	body.collision_layer = 1
	body.collision_mask = 0
	(stage if parent == null else parent).add_child(body)
	body.global_position = at


func _sync() -> void:
	await physics_frame
	await physics_frame


func _clear() -> void:
	stage.queue_free()
	await process_frame
	await physics_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
