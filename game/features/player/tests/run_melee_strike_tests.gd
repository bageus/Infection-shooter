extends SceneTree
## Melee key (ADR-0066): hand jab beside an enemy, kick otherwise; the kick
## breaks loot crates and throws loose items; two seconds between strikes.

const MELEE := preload("res://game/features/player/player_melee.gd")
const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")
const MODEL := preload("res://models/objects/characters/soldier_animated.glb")

var failures := 0


class Host:
	extends Node
	var player: CharacterBody3D
	var enemies: Array[Node3D] = []

	func _enemies_near(_center: Vector3, _radius: float, _nearest_first: bool = false) -> Array[Node3D]:
		return enemies

	static func _body_radius(_body: Node) -> float:
		return 0.4

	func _scented(_enemy: Node, amount: float) -> float:
		return amount


class Enemy:
	extends Node3D
	var damage := 0.0

	func take_damage(amount: float) -> void:
		damage += amount


class Crate:
	extends RigidBody3D
	var hits := 0.0

	func has_loot() -> bool:
		return true

	func break_by_strike(_at: Vector3, _direction: Vector3) -> void:
		hits += 10000.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Host.new()
	root.add_child(host)
	var player := CharacterBody3D.new()
	root.add_child(player)
	player.add_child(Node3D.new())
	player.get_child(0).name = "AimPivot"
	host.player = player
	var melee := MELEE.new()
	melee.configure(host)
	var driver := DRIVER.new()
	driver.name = "AnimationDriver"
	var body := MODEL.instantiate() as Node3D
	body.name = "Body"
	player.add_child(body)
	player.add_child(driver)
	var crate := Crate.new()
	crate.gravity_scale = 0.0
	var crate_shape := CollisionShape3D.new()
	crate_shape.shape = BoxShape3D.new()
	crate.add_child(crate_shape)
	crate.position = Vector3(0, 0.6, -1.0)
	root.add_child(crate)
	var chair := RigidBody3D.new()
	chair.gravity_scale = 0.0
	chair.mass = 5.0
	var chair_shape := CollisionShape3D.new()
	chair_shape.shape = BoxShape3D.new()
	chair.add_child(chair_shape)
	chair.position = Vector3(0.0, 0.6, -1.2)
	root.add_child(chair)
	await physics_frame
	await physics_frame

	_expect(melee.start() == MELEE.KICK, "With no enemy nearby the strike is a kick.")
	_expect(melee.start() == &"", "A second press inside two seconds does nothing.")
	_expect(driver.is_striking(), "The kick pose plays on the skeleton.")
	melee.tick(0.1)
	_expect(crate.hits == 0.0, "The crate holds until the foot lands.")
	melee.tick(0.2)
	_expect(crate.hits >= 1000.0, "The kick breaks a loot crate at once.")
	await physics_frame
	_expect(chair.linear_velocity.length() > 1.0 and chair.linear_velocity.z < 0.0, "The kick throws a loose item away from the character.")
	melee.tick(1.6)
	_expect(melee.start() == &"", "Still blocked at 1.9 s after the press.")
	melee.tick(0.2)
	var enemy := Enemy.new()
	enemy.position = Vector3(0, 0, -1.0)
	root.add_child(enemy)
	host.enemies = [enemy]
	_expect(melee.start() == MELEE.PUNCH, "With an enemy beside the player the strike is a left-hand jab.")
	melee.tick(0.3)
	_expect(enemy.damage > 0.0, "The jab hurts the enemy in front.")
	print("melee strike failures: ", failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
