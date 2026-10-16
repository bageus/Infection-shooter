extends SceneTree
const ENEMY := preload("res://game/features/infected/public/infected_capsule.tscn")
const BULLET := preload("res://game/features/combat/public/prototype_bullet.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var enemies: Array[Node3D] = []
	for x in [2.0, 4.0]:
		var enemy := ENEMY.instantiate() as Node3D
		stage.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.position = Vector3(x, 1, 0)
		enemy.set("max_health", 500.0)
		enemy.set("health", 500.0)
		enemy.call("configure_world", stage, null)
		enemies.append(enemy)
	var bullet := BULLET.instantiate() as Node3D
	stage.add_child(bullet)
	bullet.position = Vector3(0, 1, 0)
	bullet.call("configure_world", stage, null)
	bullet.call("setup_projectile", Vector3.RIGHT, null, 20.0, 360.0, 10.0, "SNIPER RIFLE")
	bullet.set_physics_process(false)
	await physics_frame
	await physics_frame
	for i in 3:
		bullet.call("_physics_process", 1.0 / 60.0)
	for enemy in enemies:
		_check(float(enemy.get("health")) < 500.0, "Real public infected takes damage through the preceding body")
	var runtime := stage.get_node_or_null("CombatPenetrationFx")
	_check(runtime != null and runtime.get_child_count() == 2, "Real infected geometry produces an exit blood burst behind each body")
	if runtime != null:
		for node in runtime.get_children():
			_check(node.get_meta("exit_material", "") == "flesh", "Live infected cannot produce object sparks")
	stage.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	print("Body penetration integration tests: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
