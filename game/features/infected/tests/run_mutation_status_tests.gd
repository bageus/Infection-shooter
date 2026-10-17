extends SceneTree
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
var failures := 0
var stage: Node3D


func _init() -> void: call_deferred("_run")

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	var enemy := _enemy(Vector3(0, 0.05, 0))
	await physics_frame
	enemy.call("apply_skill_push", Vector3.RIGHT, 3.0)
	for frame in 35:
		enemy.call("_physics_process", 1.0 / 60.0)
		await physics_frame
	_expect(absf(enemy.position.x - 3.0) < 0.03, "Skill push travels three actual metres")
	_box(Vector3(5, 1, 0), Vector3(0.2, 2, 4))
	await physics_frame
	enemy.call("apply_skill_push", Vector3.RIGHT, 5.0)
	for frame in 35:
		enemy.call("_physics_process", 1.0 / 60.0)
		await physics_frame
	_expect(enemy.position.x > 3.0 and enemy.position.x < 4.8, "A wall limits knockback without tunnelling")
	enemy.call("apply_blast_stun", 1.2, 1.0)
	enemy.call("_physics_process", 0.5)
	enemy.call("apply_blast_stun", 1.2, 1.0)
	_expect(is_equal_approx(float(enemy.get("_blast_stun_remaining")), 1.2), "Repeated stun refreshes instead of adding durations")
	await _poison()
	stage.queue_free()
	await process_frame
	await process_frame
	print("Mutation status tests: %d failures" % failures)
	quit(failures)

func _enemy(at: Vector3) -> CharacterBody3D:
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.position = at
	enemy.set_physics_process(false)
	enemy.set("max_health", 500.0)
	enemy.set("health", 500.0)
	return enemy

func _poison() -> void:
	var infected := _enemy(Vector3(-5, 0.05, 0))
	var near := _enemy(Vector3(-2, 0.05, 0))
	var far := _enemy(Vector3(-9.01, 0.05, 0))
	infected.set("health", 20.0)
	infected.call("apply_skill_infection", 3.0, 10.0)
	infected.call("_physics_process", 0.5)
	_expect(is_equal_approx(float(infected.get("health")), 15.0), "Infection applies exactly10 damage/s")
	infected.call("_physics_process", 1.5)
	_expect(infected.has_meta("mutation_infection_death") and float(near.get("health")) == 460.0 and float(far.get("health")) == 500.0, "Death from infection explodes40 damage within4m only")
	infected.call("_physics_process", 5.0)
	_expect(float(near.get("health")) == 460.0, "Infection death cannot explode twice")
	var shot := _enemy(Vector3(-5, 0.05, 5))
	var witness := _enemy(Vector3(-3, 0.05, 5))
	shot.call("apply_skill_infection", 3.0, 10.0)
	shot.call("take_damage", 1000.0)
	shot.call("_physics_process", 5.0)
	_expect(not shot.has_meta("mutation_infection_death") and float(witness.get("health")) == 500.0, "A bullet/ordinary hit death during infection does not explode")
	var expired := _enemy(Vector3(10, 0.05, 0))
	expired.call("apply_skill_infection", 3.0, 10.0)
	expired.call("_physics_process", 8.0)
	_expect(float(expired.get("health")) == 470.0, "A coarse frame cannot extend infection beyond its three seconds")
	await process_frame

func _box(at: Vector3, dimensions: Vector3) -> void:
	var box := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = dimensions
	shape.shape = hull
	box.add_child(shape)
	stage.add_child(box)
	box.position = at

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
