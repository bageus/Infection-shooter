extends SceneTree
## Titan rock throw: it rips a rock out of the floor, throws it at the point the
## player stood at release, and the rock misses a player who has moved away.

const TITAN := preload("res://game/features/infected/public/infected_titan.tscn")
var _failures := 0

class FakePlayer:
	extends StaticBody3D
	var damage_taken := 0.0
	func take_damage(amount: float, _kind: String = "physical") -> void:
		damage_taken += amount


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
		await _round(stage, dodge)
	print("Titan throw tests, failures: %d" % _failures)
	quit(_failures)


func _round(stage: Node3D, dodge: bool) -> void:
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
	enemy.set("_throw_cooldown", 0.0)
	enemy.call("set_target", target)
	var animation := enemy.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	await physics_frame
	await physics_frame
	_expect(animation.current_animation == "Throw", "Titan starts the throw clip at range.")
	var length := animation.get_animation("Throw").length
	await create_timer(length * 0.5).timeout
	_expect(stage.get_node_or_null("TitanRock") != null or enemy.get_parent().get_node_or_null("TitanRock") != null, "A rock is held after the grab.")
	if dodge:
		await create_timer(length * 0.2).timeout
		target.global_position = Vector3(6.0, 1.0, -8.0)
	await create_timer(length * 0.5 + 1.2).timeout
	if dodge:
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
