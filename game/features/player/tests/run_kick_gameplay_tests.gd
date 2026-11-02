extends SceneTree
## The melee key through the real mutation-effects node: each kick breaks only the nearest loot crate.

const MUTATION := preload("res://game/features/player/mutation_skill_effects.gd")
const DRIVER := preload("res://game/features/character_animation/public/character_animation_driver.gd")

var failures := 0


class Body extends CharacterBody3D:
	var health := 100.0
	var max_health := 100.0


class Runtime extends Node:
	signal skill_cast(skill_id: String)
	signal tree_changed
	signal mutation_changed(amount: float, threshold: float)

	func has_skill(_skill_id: String) -> bool:
		return false

	func is_control_lost() -> bool:
		return false


class Crate extends RigidBody3D:
	var hits := 0.0

	func has_loot() -> bool:
		return true

	func break_by_strike(_at: Vector3, _direction: Vector3) -> void:
		hits += 10000.0
		collision_layer = 0 # a broken crate leaves the kick's query, as the real prop does


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := Body.new()
	root.add_child(player)
	player.add_child(Node3D.new())
	player.get_child(0).name = "AimPivot"
	player.add_child(DRIVER.new())
	player.get_child(1).name = "AnimationDriver"
	var mutation = MUTATION.new()
	root.add_child(mutation)
	mutation.configure(player, Runtime.new(), [] as Array[Node3D])
	var crates: Array[Crate] = []
	for distance in [1.0, 1.9, 2.8]:
		var crate := Crate.new()
		crate.gravity_scale = 0.0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		crate.add_child(shape)
		crate.position = Vector3(0, 0.6, -distance)
		root.add_child(crate)
		crates.append(crate)
	await physics_frame
	await physics_frame
	for step in crates.size():
		# Each kick comes from one metre in front of the next crate, facing -Z.
		player.global_position = crates[step].global_position + Vector3(0.0, -0.6, 1.0)
		await physics_frame
		mutation.call("melee")
		await create_timer(0.5).timeout
		var broken := 0
		for crate in crates:
			if crate.hits > 0.0:
				broken += 1
		_expect(broken == step + 1, "Kick %d breaks exactly one more crate (%d broken)." % [step + 1, broken])
		await create_timer(2.2).timeout
	print("gameplay kick failures: ", failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
