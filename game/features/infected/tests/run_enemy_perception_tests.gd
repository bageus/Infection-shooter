extends SceneTree
## Infected notice the player by sight or sound only; classes smash props by tier.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const REVENANT := preload("res://game/features/infected/public/infected_revenant.tscn")
const TITAN := preload("res://game/features/infected/public/infected_titan.tscn")
const BREAKER := preload("res://game/features/infected/obstacle_breaker.gd")
var failures := 0
var stage: Node3D


class Target:
	extends Node3D
	func take_damage(_amount: float, _kind := "physical") -> void:
		pass


class Prop:
	extends StaticBody3D
	var hits := 0
	func take_melee_hit(_damage: float, _position: Vector3, _direction: Vector3) -> void:
		hits += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.time_scale = 4.0
	await _fresh_stage()
	await _sight()
	await _hearing()
	await _ally_cry()
	await _forced_target()
	_tiers()
	await _breach(REVENANT, true)
	await _breach(HUNGER, false)
	Engine.time_scale = 1.0
	print("Enemy perception tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _fresh_stage() -> void:
	if stage != null:
		stage.queue_free()
		await process_frame
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	stage.add_child(floor_body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)


func _spawn(scene: PackedScene, at: Vector3, player: Node3D) -> CharacterBody3D:
	var enemy := scene.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = at
	enemy.call("watch_target", player)
	return enemy


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	stage.add_child(wall)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	wall.position = center
	return wall


func _sight() -> void:
	var player := Target.new()
	stage.add_child(player)
	player.position = Vector3(0, 0.1, -30)
	var far := _spawn(HUNGER, Vector3(0, 0.1, 0), player)
	await _frames(40)
	_check(not far.call("is_alerted"), "An enemy 30 m away does not notice the player")
	_check(_flat(far.global_position, Vector3.ZERO) < 0.3, "An unaware enemy stands still")
	player.position = Vector3(0, 0.1, -9)
	await _frames(40)
	_check(far.call("is_alerted"), "An enemy facing the player in the open sees them")
	await _fresh_stage()
	player = Target.new()
	stage.add_child(player)
	player.position = Vector3(0, 0.1, 9)
	var back := _spawn(HUNGER, Vector3(0, 0.1, 0), player)
	await _frames(40)
	_check(not back.call("is_alerted"), "An enemy does not see the player behind its back")
	player.position = Vector3(0, 0.1, 2.0)
	await _frames(30)
	_check(back.call("is_alerted"), "An enemy notices the player standing right behind it")
	await _fresh_stage()
	player = Target.new()
	stage.add_child(player)
	player.position = Vector3(0, 0.1, -9)
	_wall(Vector3(0, 1.5, -4), Vector3(8, 3, 0.4))
	var hidden := _spawn(HUNGER, Vector3(0, 0.1, 0), player)
	await _frames(40)
	_check(not hidden.call("is_alerted"), "A wall hides the player")


func _hearing() -> void:
	await _fresh_stage()
	var player := Target.new()
	stage.add_child(player)
	player.position = Vector3(0, 0.1, -60)
	_wall(Vector3(0, 1.5, -6), Vector3(8, 3, 0.4))
	var enemy := _spawn(HUNGER, Vector3(0, 0.1, 0), player)
	await _frames(5)
	var home := enemy.global_position
	get_first_node_in_group("infected_alive").call("hear_noise", Vector3(-3, 0.1, -3), 10.0)
	await _frames(60)
	_check(not enemy.call("is_alerted"), "A shot sends the enemy to the noise, it does not start a chase")
	_check(_flat(enemy.global_position, home) > 0.5, "The enemy walks toward the noise")
	await _frames(900)
	_check(not enemy.call("is_alerted"), "Nothing found at the noise: still unaware")
	_check(_flat(enemy.global_position, home) < 1.2, "The enemy walks back home when the noise leaves nobody")
	enemy.call("hear_noise", Vector3(0, 0.1, 40), 10.0)
	await _frames(20)
	_check(_flat(enemy.global_position, home) < 1.3, "A shot out of range is not heard")


func _ally_cry() -> void:
	await _fresh_stage()
	var player := Target.new()
	stage.add_child(player)
	player.position = Vector3(0, 0.1, -9)
	var seer := _spawn(HUNGER, Vector3(0, 0.1, 0), player)
	var friend := _spawn(HUNGER, Vector3(6, 0.1, 6), player)
	_wall(Vector3(3, 1.5, 3), Vector3(0.4, 3, 6))
	await _frames(45)
	_check(seer.call("is_alerted"), "The enemy that sees the player is alerted")
	_check(friend.call("is_alerted"), "Its nearby neighbour joins the chase after the cry")
	var far_friend := _spawn(HUNGER, Vector3(40, 0.1, 40), player)
	await _frames(10)
	_check(not far_friend.call("is_alerted"), "A distant enemy does not hear the cry")


func _forced_target() -> void:
	await _fresh_stage()
	var player := Target.new()
	stage.add_child(player)
	player.position = Vector3(0, 0.1, -40)
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = Vector3(0, 0.1, 0)
	enemy.set_target(player)
	await _frames(30)
	_check(enemy.call("is_alerted"), "set_target forces the chase regardless of sight")
	_check(enemy.global_position.z < -0.5, "A forced enemy runs at the player")


func _tiers() -> void:
	var chair := Prop.new()
	chair.name = "06_office_chair"
	var table := Prop.new()
	table.name = "07_table"
	var rock := StaticBody3D.new()
	var none := BREAKER.new()
	var small := BREAKER.new()
	small.tier = 1
	var big := BREAKER.new()
	big.tier = 2
	_check(not none.can_break(chair) and not none.can_break(table), "Basic infected smash nothing")
	_check(small.can_break(chair) and not small.can_break(table), "Revenant smashes a chair but not a table")
	_check(big.can_break(chair) and big.can_break(table), "Titan and above smash tables too")
	_check(not big.can_break(rock), "Non-destructible bodies are never targets")
	for node in [chair, table, rock]:
		node.free()


func _breach(scene: PackedScene, expect_hits: bool) -> void:
	await _fresh_stage()
	_wall(Vector3(-2.2, 1.5, -6), Vector3(0.4, 3, 40))
	_wall(Vector3(2.2, 1.5, -6), Vector3(0.4, 3, 40))
	var chair := Prop.new()
	chair.name = "06_office_chair"
	chair.collision_layer = 1
	stage.add_child(chair)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 1.5, 0.6)
	shape.shape = box
	chair.add_child(shape)
	chair.position = Vector3(0, 0.75, -4)
	var player := Target.new()
	stage.add_child(player)
	player.position = Vector3(0, 0.1, -9)
	var enemy := scene.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = Vector3(0, 0.1, 0)
	enemy.set_target(player)
	await _frames(900)
	if expect_hits:
		_check(chair.hits > 0, "A revenant stuck behind a chair smashes it")
	else:
		_check(chair.hits == 0, "A basic infected never attacks props")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error("FAIL: " + message)
