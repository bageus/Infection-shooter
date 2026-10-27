extends SceneTree
## Endless mode: round scaling and a director that restarts its queues once a round is cleared.

const CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const ENDLESS := preload("res://game/features/spawning/domain/endless_waves.gd")
const DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
const POINT := preload("res://game/features/spawning/public/spawn_point.tscn")
var failures := 0
var _rounds: Array[int] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_scaling()
	await _director()
	print("Endless tests: %d failures" % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _scaling() -> void:
	var base := {"enemies": [{"enemy": "hunger", "count": 10}], "interval": 1.0, "health": 100.0, "damage": 100.0}
	var first := ENDLESS.queue_for_round(base, 1)
	_check(first["enemies"] == [{"enemy": "hunger", "count": 10}] and first["health"] == 100.0, "round 1 is the authored queue")
	var fifth := ENDLESS.queue_for_round(base, 5)
	_check(fifth["enemies"][0]["count"] == 18 and fifth["health"] == 120.0 and fifth["interval"] < 1.0, "round 5 is bigger, tougher and faster")
	var late := ENDLESS.queue_for_round(base, 500)
	_check(late["enemies"][0]["count"] == CONFIG.COUNT_MAX and late["health"] == CONFIG.STAT_MAX and late["interval"] >= ENDLESS.INTERVAL_FLOOR, "growth stops at the config limits")
	_check(ENDLESS.first_queue_for_round(base, 3)["enemies"].size() == 1, "no heavy kinds before round 4")
	_check(ENDLESS.first_queue_for_round(base, 8)["enemies"].map(func(e: Dictionary) -> String: return e["enemy"]) == ["hunger", "brute", "titan"], "heavy kinds join with the rounds")


func _alive(enemies: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for enemy in enemies.get_children():
		if enemy.has_meta(&"spawned_by") and not enemy.call("is_dead"):
			found.append(enemy)
	return found


func _wait_for(enemies: Node3D, count: int) -> bool:
	for step in 240:
		await physics_frame
		if _alive(enemies).size() == count:
			return true
	return false


func _director() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	stage.add_child(floor_body)
	var enemies := Node3D.new()
	stage.add_child(enemies)
	var player := Node3D.new()
	player.position = Vector3(10, 1, 0)
	stage.add_child(player)
	var point := POINT.instantiate() as Node3D
	point.set_meta("planning_object_id", "endless_test")
	stage.add_child(point)
	point.call("configure_spawn", {"enemy": "hunger", "count": 5, "interval": 0.1, "rule": "stream"})
	point.position = Vector3(-6, 0, 0)
	var director := DIRECTOR.new()
	director.endless = true
	stage.add_child(director)
	director.round_started.connect(func(number: int) -> void: _rounds.append(number))
	director.configure(enemies, player)
	director.arm()
	_check(await _wait_for(enemies, 5), "round 1 spawns the authored 5 without any trigger")
	for enemy in _alive(enemies):
		enemy.call("take_damage", 9999.0)
	_check(await _wait_for(enemies, 6), "clearing round 1 starts round 2 with 6")
	for enemy in _alive(enemies):
		enemy.call("take_damage", 9999.0)
	_check(await _wait_for(enemies, 7), "round 3 has 7")
	_check(_rounds == [1, 2, 3] and director.round_number == 3, "round_started fires once per round")
	director.disarm()
	_check(director.round_number == 0, "disarm resets the rounds")
	stage.queue_free()
	await process_frame
