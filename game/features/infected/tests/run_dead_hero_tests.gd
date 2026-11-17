extends SceneTree
## Infected leave a dead hero alone: a living target is hit, a target without health is neither chased nor hit.
const REVENANT := preload("res://game/features/infected/public/infected_revenant.tscn")
class Target extends Node3D:
	var health := 100.0
	var received := 0.0
	func take_damage(amount: float) -> void:
		received += amount
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(80, 1, 80)
	floor_body.add_child(shape)
	floor_body.position.y = -.5
	stage.add_child(floor_body)
	var target := Target.new()
	target.add_to_group("player")
	stage.add_child(target)
	var enemy := REVENANT.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.position = Vector3(0, .05, 0.8)
	enemy.set_target(target)
	enemy.hear_alert(target.global_position, 50.0)
	for _frame in 240:
		await physics_frame
	_check(target.received > 0.0, "A living hero is attacked (%.0f damage)." % target.received)
	target.health = 0.0
	target.received = 0.0
	enemy.position = Vector3(3.0, .05, 3.0)
	var start := enemy.position
	for _frame in 240:
		await physics_frame
	_check(target.received == 0.0, "A dead hero takes no more blows.")
	_check(Vector2(enemy.position.x - start.x, enemy.position.z - start.z).length() < 0.2, "The enemy no longer chases a dead hero.")
	stage.free()
	await process_frame
	print("Dead hero tests: %d failures" % failures)
	quit(failures)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: ", message)
