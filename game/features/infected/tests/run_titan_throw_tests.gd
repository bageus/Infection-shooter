extends SceneTree
## Titan rock throw: it rips a rock out of the floor, throws it at the point the
## player stood at release, and the rock misses a player who has moved away.

const TITAN := preload("res://game/features/infected/public/infected_titan.tscn")
var _failures := 0

class FakePlayer:
	extends StaticBody3D
	var damage_taken := 0.0
	var health := 100.0
	var armor := 0.0
	var stuns: Array = []
	func take_damage(amount: float, _kind: String = "physical") -> void:
		damage_taken += amount
		health -= amount
		armor = 0.0
	func apply_blast_stun(duration: float, _intensity: float) -> void:
		stuns.append(duration)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(80, 1, 80)
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.5
	for dodge in [false, true]:
		await _round(stage, dodge, false)
	await _round(stage, false, true)
	await _test_stun_and_shape(stage)
	print("Titan throw tests, failures: %d" % _failures)
	quit(_failures)


func _round(stage: Node3D, dodge: bool, walled: bool) -> void:
	var enemy := TITAN.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = Vector3(0, 1.4, 0)
	var target := FakePlayer.new()
	target.add_to_group("player")
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	target.add_child(shape)
	stage.add_child(target)
	target.global_position = Vector3(0, 1.0, -8.0)
	var wall: StaticBody3D
	if walled:
		# A wall appears after the throw starts (the line was clear at the decision).
		wall = StaticBody3D.new()
		var wall_shape := CollisionShape3D.new()
		wall_shape.shape = BoxShape3D.new()
		(wall_shape.shape as BoxShape3D).size = Vector3(10, 8, 0.5)
		wall.add_child(wall_shape)
		stage.add_child(wall)
		wall.global_position = Vector3(0, 3, -5.0)
		wall.collision_layer = 0
	enemy.set("_throw_cooldown", 0.0)
	enemy.call("set_target", target)
	var animation := enemy.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	await physics_frame
	await physics_frame
	_expect(animation.current_animation == "Throw", "Titan starts the throw clip at range.")
	var length := animation.get_animation("Throw").length
	if walled:
		wall.collision_layer = 1
	await create_timer(length * 0.5).timeout
	_expect(stage.get_node_or_null("TitanRock") != null or enemy.get_parent().get_node_or_null("TitanRock") != null, "A rock is held after the grab.")
	if dodge:
		await create_timer(length * 0.3).timeout
		target.global_position = Vector3(6.0, 1.0, -8.0)
	await create_timer(length * 0.3 + 1.2).timeout
	if walled:
		_expect(target.damage_taken == 0.0, "A wall between the Titan and the player stops the rock.")
		wall.queue_free()
	elif dodge:
		_expect(target.damage_taken == 0.0, "A player who moved after the release is not hit.")
	else:
		_expect(target.damage_taken > 0.0, "A player who stays put is hit.")
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)


# A centred rock hit stuns for 1 s, a glancing one for 0.5 s, and every rock has its own shape.
func _test_stun_and_shape(stage: Node3D) -> void:
	var target := FakePlayer.new()
	target.add_to_group("player")
	stage.add_child(target)
	target.global_position = Vector3(0, 1.0, 0)
	for miss in [0.0, 1.0]:
		var rock := preload("res://game/features/infected/titan_rock.gd").new() as Node3D
		stage.add_child(rock)
		rock.set("damage", 10.0)
		rock.call("launch", Vector3(0, 1, -8), target.global_position + Vector3(miss, 0, 0), 0.2)
		await create_timer(0.5).timeout
	_expect(target.stuns.size() == 2, "Each rock hit stuns the player.")
	if target.stuns.size() == 2:
		_expect(is_equal_approx(target.stuns[0], 1.0), "A centred hit stuns for 1 s.")
		_expect(target.stuns[1] >= 0.5 and target.stuns[1] < 0.6, "A glancing hit stuns for about 0.5 s.")
	var sizes := {}
	for i in 5:
		var rock := preload("res://game/features/infected/titan_rock.gd").new() as Node3D
		stage.add_child(rock)
		sizes[((rock.get_child(0) as MeshInstance3D).mesh as ArrayMesh).get_aabb().size] = true
	_expect(sizes.size() >= 4, "Rocks differ in shape.")
	target.queue_free()
