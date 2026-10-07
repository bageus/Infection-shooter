extends SceneTree
## Debris that fell before an infected spawned stays contactless for it too,
## and only living infected are counted as alive.
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const SEVERED := preload("res://game/features/infected/severed_part.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var piece := RigidBody3D.new()
	piece.add_to_group(SEVERED.CONTACTLESS_GROUP)
	stage.add_child(piece)
	var decoration := Node3D.new()
	decoration.add_to_group(SEVERED.CONTACTLESS_GROUP)
	stage.add_child(decoration)
	var enemy := HUNGER.instantiate() as PhysicsBody3D
	stage.add_child(enemy)
	await process_frame
	_check(enemy.get_collision_exceptions().has(piece), "A late infected ignores debris that fell before it")
	_check(enemy.is_in_group("infected_alive"), "A living infected is in the alive group")
	enemy.call("take_damage", 100000.0)
	await process_frame
	_check(not enemy.is_in_group("infected_alive") and enemy.is_in_group("infected"), "A dying infected leaves the alive count but keeps its corpse group")
	stage.queue_free()
	await process_frame
	print("Late spawn debris tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
