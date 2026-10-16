extends SceneTree
const BULLET := preload("res://game/features/combat/public/prototype_bullet.tscn")
const BURST := preload("res://game/features/combat/penetration_burst.gd")

class Surface:
	extends StaticBody3D
	var material := "glass"
	var hits := 0
	var stop := false
	func get_projectile_material(_shape: int) -> String:
		return material
	func take_projectile_hit(_damage: float, _point: Vector3, _normal: Vector3, _direction: Vector3, _weapon: String) -> bool:
		hits += 1
		return stop

class Enemy:
	extends CharacterBody3D
	var hits := 0
	var lethal := false
	func take_damage(_damage: float) -> void:
		pass
	func take_projectile_damage(_damage: float, _point: Vector3, _direction: Vector3, _weapon: String) -> void:
		hits += 1
		if lethal:
			remove_from_group("infected_alive")
			collision_layer = 0

var failures := 0
var stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for weapon in ["PISTOL", "UZI", "SHOTGUN", "AK", "M4", "MINIGUN", "SNIPER RIFLE"]:
		await _body(weapon, false)
	await _body("SNIPER RIFLE", true)
	await _thick_body()
	await _range_inside()
	await _objects()
	await _blocked()
	await _dense_chain()
	await _caps_and_strength()
	await create_timer(0.2).timeout
	print("Penetration exit tests: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _start() -> void:
	stage = Node3D.new()
	root.add_child(stage)


func _shape(body: CollisionObject3D, width: float) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 1, 1)
	collision.shape = box
	body.add_child(collision)


func _enemy(x: float, width: float = 0.6) -> Enemy:
	var body := Enemy.new()
	body.collision_layer = 2
	body.collision_mask = 0
	_shape(body, width)
	stage.add_child(body)
	body.position = Vector3(x, 1, 0)
	body.add_to_group("infected_alive")
	return body


func _surface(x: float, material: String, width: float = 0.1) -> Surface:
	var body := Surface.new()
	body.material = material
	body.collision_layer = 1
	body.collision_mask = 0
	_shape(body, width)
	stage.add_child(body)
	body.position = Vector3(x, 1, 0)
	return body


func _bullet(weapon: String, speed: float = 120.0, distance: float = 10.0) -> Node3D:
	var bullet := BULLET.instantiate() as Node3D
	stage.add_child(bullet)
	bullet.position = Vector3(0, 1, 0)
	bullet.call("configure_world", stage, null)
	bullet.call("setup_projectile", Vector3.RIGHT, null, 20.0, speed, distance, weapon)
	bullet.set_physics_process(false)
	return bullet


func _fx(kind: String) -> Array[Node]:
	var result: Array[Node] = []
	var runtime := stage.get_node_or_null("CombatPenetrationFx")
	if runtime != null:
		for child in runtime.get_children():
			if (str(child.get_meta("exit_material", "")) == "flesh") == (kind == "ExitBlood"):
				result.append(child)
	return result


func _finish() -> void:
	stage.queue_free()
	await process_frame
	await process_frame


func _body(weapon: String, lethal: bool) -> void:
	_start()
	var enemy := _enemy(1)
	enemy.lethal = lethal
	var wall := _surface(2, "solid")
	var bullet := _bullet(weapon)
	await physics_frame
	await physics_frame
	for i in 4:
		if not bullet.is_queued_for_deletion():
			bullet.call("_physics_process", 1.0 / 60)
	var penetrates := weapon in ["AK", "M4", "MINIGUN", "SNIPER RIFLE"]
	_check(enemy.hits == 1, "A body is damaged once, including lethal callbacks")
	_check(wall.hits == (1 if penetrates else 0), "Only sufficiently powerful bullets reach the wall behind a body")
	_check(_fx("ExitBlood").size() == (1 if penetrates else 0), "Only actual body penetration emits exit blood")
	if penetrates:
		var blood := _fx("ExitBlood")[0] as GPUParticles3D
		_check(blood.global_position.x > 1.3 and blood.global_position.x < 1.33, "Blood starts behind the body's exact back surface")
		_check((blood.process_material as ParticleProcessMaterial).direction.dot(Vector3.RIGHT) > 0.99, "Blood sprays forward, away from shooter")
	await _finish()


func _thick_body() -> void:
	_start()
	var enemy := _enemy(1.5, 2.0)
	var bullet := _bullet("SNIPER RIFLE", 6)
	await physics_frame
	await physics_frame
	for i in 15:
		bullet.call("_physics_process", 1.0 / 60)
	_check(enemy.hits == 1 and _fx("ExitBlood").is_empty(), "No repeated damage or premature exit while travelling inside a thick body")
	for i in 15:
		bullet.call("_physics_process", 1.0 / 60)
	_check(enemy.hits == 1 and _fx("ExitBlood").size() == 1, "Exactly one exit burst after crossing the back surface")
	await _finish()


func _range_inside() -> void:
	_start()
	_enemy(1.5, 2.0)
	var bullet := _bullet("SNIPER RIFLE", 120, 1.0)
	await physics_frame
	await physics_frame
	for i in 3:
		if not bullet.is_queued_for_deletion():
			bullet.call("_physics_process", 1.0 / 60)
	_check(_fx("ExitBlood").is_empty(), "Range ending inside the body cannot produce an exit")
	await _finish()


func _objects() -> void:
	_start()
	var first := _surface(0.5, "wood")
	var second := _surface(1.0, "tech")
	var wall := _surface(1.2, "solid")
	var bullet := _bullet("SNIPER RIFLE")
	await physics_frame
	await physics_frame
	for i in 5:
		if not bullet.is_queued_for_deletion():
			bullet.call("_physics_process", 1.0 / 60)
	_check(first.hits == 1 and second.hits == 1 and wall.hits == 1, "Sequential objects preserve hits and blocking wall")
	_check(_fx("ExitSparks").size() == 2, "Every penetrated object has one exit spark burst")
	for node in _fx("ExitSparks"):
		var particles := node as GPUParticles3D
		var material := particles.draw_pass_1.surface_get_material(0) as StandardMaterial3D
		_check(material.emission_energy_multiplier < 1.0 and particles.lifetime < 0.3, "Exit sparks are dim and short, without an entry flash light")
	await _finish()


func _blocked() -> void:
	_start()
	var metal := _surface(0.5, "metal")
	var bullet := _bullet("PISTOL")
	await physics_frame
	await physics_frame
	bullet.call("_physics_process", 1.0 / 60)
	_check(metal.hits == 1 and _fx("ExitSparks").is_empty(), "Insufficient energy cannot create an exit spark")
	await _finish()


func _dense_chain() -> void:
	_start()
	var surfaces: Array[Surface] = []
	for i in 7:
		surfaces.append(_surface(0.2 + i * 0.15, "glass", 0.02))
	var wall := _surface(1.3, "solid", 0.02)
	var bullet := _bullet("SNIPER RIFLE", 240.0)
	await physics_frame
	await physics_frame
	for tick in 8:
		if bullet.is_queued_for_deletion():
			break
		var before := wall.hits
		for body in surfaces:
			before += body.hits
		bullet.call("_physics_process", 1.0 / 60)
		var after := wall.hits
		for body in surfaces:
			after += body.hits
		_check(after - before <= 2, "Two geometry rays per contact fit inside the existing five-ray budget")
	_check(wall.hits == 1 and _fx("ExitSparks").size() == 7, "Deferred dense chain emits each exit once and still stops at the wall")
	for body in surfaces:
		_check(body.hits == 1, "Deferred contacts never duplicate damage")
	await _finish()


func _caps_and_strength() -> void:
	_start()
	BURST.spawn(stage, Vector3.ZERO, Vector3.RIGHT, "flesh", 26)
	BURST.spawn(stage, Vector3.ZERO, Vector3.RIGHT, "flesh", 78)
	var blood := _fx("ExitBlood")
	_check((blood[1] as GPUParticles3D).amount > (blood[0] as GPUParticles3D).amount, "Higher remaining power produces more blood")
	var weak := (blood[0] as GPUParticles3D).process_material as ParticleProcessMaterial
	var strong := (blood[1] as GPUParticles3D).process_material as ParticleProcessMaterial
	_check(strong.initial_velocity_max > weak.initial_velocity_max, "Higher remaining power throws blood further")
	for i in 50:
		BURST.spawn(stage, Vector3.ZERO, Vector3.RIGHT, "wood", 80)
	_check(stage.get_node("CombatPenetrationFx").get_child_count() == 24, "Mission-local particle emitter cap is enforced")
	await create_timer(1.0).timeout
	_check(stage.get_node("CombatPenetrationFx").get_child_count() == 0, "Emitters expire and release budget")
	await _finish()
