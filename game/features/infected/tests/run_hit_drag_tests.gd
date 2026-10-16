extends SceneTree
const PACE := preload("res://game/features/infected/chase_pace.gd")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const TITAN := preload("res://game/features/infected/public/infected_titan.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var weak := PACE.new()
	var heavy := PACE.new()
	_check(weak.hit(16.0, 45.0) > heavy.hit(16.0, 260.0), "Same bullet bends a weaker enemy more")
	var maximum: float = weak.hit_penalty
	for i in 100:
		weak.hit(100.0, 45.0)
	_check(is_equal_approx(weak.hit_penalty, maximum) and weak.hit_penalty < 0.16, "Repeated hits do not stack a stun or stop movement")
	weak.recover_hit(0.2)
	_check(is_zero_approx(weak.hit_penalty), "Speed fully recovers within 0.2 seconds")
	await _enemy(HUNGER)
	await _enemy(TITAN)
	await create_timer(0.2).timeout
	print("Hit drag tests: %d failures" % failures)
	quit(1 if failures else 0)

func _enemy(scene: PackedScene) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var target := Node3D.new()
	stage.add_child(target)
	target.position = Vector3(0, 0, -20)
	var enemy = scene.instantiate()
	stage.add_child(enemy)
	enemy.set_target(target)
	enemy.set_physics_process(false)
	enemy.gravity_acceleration = 0.0
	enemy.charge_distance = 0.0
	enemy.set("_cached_desired", Vector3.FORWARD * enemy.move_speed)
	var pace = enemy.get("_pace")
	enemy.take_projectile_damage(5.0, enemy.position + Vector3(0, 1.3, -0.1), Vector3.BACK, "PISTOL")
	_check(pace.hit_penalty > 0.0, "Real projectile damage applies drag")
	var driver = enemy.get_node("AnimationDriver")
	_check(driver.hit_reaction.get("_velocity").length() > 0.0, "Real hit goes to the directional torso spring, including Hunger")
	var before: Vector3 = enemy.position
	enemy._physics_process(1.0 / 60.0)
	_check(enemy.position.z < before.z and enemy.velocity.z < 0.0, "An injured enemy still advances towards its target")
	_check(enemy.velocity.length() < enemy.move_speed and enemy.velocity.length() > enemy.move_speed * 0.8, "Brief slowdown stays small")
	for i in 20:
		enemy._physics_process(1.0 / 60.0)
	_check(is_zero_approx(pace.hit_penalty) and absf(enemy.velocity.length() - enemy.move_speed) < 0.01, "Actual chase regains full speed promptly")
	enemy.take_damage(0.05)
	_check(is_zero_approx(pace.hit_penalty), "Tiny per-frame damage does not renew drag")
	stage.queue_free()
	await process_frame
