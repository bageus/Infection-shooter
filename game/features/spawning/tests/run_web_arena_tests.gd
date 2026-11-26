extends SceneTree
## Web arena director: wave 0 (placed infected), growing waves, announcements, Horde wave ends the arena.

const DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
const POINT := preload("res://game/features/spawning/public/spawn_point.tscn")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
var failures := 0
var _announced: Array[Array] = []
var _cleared := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _arena()
	print("Web arena tests: %d failures" % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _spawned(enemies: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for enemy in enemies.get_children():
		if enemy.has_meta(&"spawned_by") and not enemy.call("is_dead"):
			found.append(enemy)
	return found


func _wait_for(enemies: Node3D, count: int) -> bool:
	for step in 400:
		await physics_frame
		if _spawned(enemies).size() == count:
			return true
	return false


func _kill_all(enemies: Node3D) -> void:
	for enemy in enemies.get_children():
		if enemy.has_method("is_dead") and not enemy.call("is_dead"):
			enemy.call("take_damage", 99999.0)
	await physics_frame


func _arena() -> void:
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
	var placed := HUNGER.instantiate() as Node3D
	enemies.add_child(placed)
	var hole := POINT.instantiate() as Node3D
	hole.set_meta("planning_object_id", "arena_hole")
	stage.add_child(hole)
	hole.call("configure_spawn", {"queues": [{"enemies": [{"enemy": "hunger", "count": 5}], "interval": 0.1}], "web": {"role": "wave", "add": 2, "min": 5, "max": 40}})
	hole.position = Vector3(-6, 0, 0)
	var boss := POINT.instantiate() as Node3D
	boss.set_meta("planning_object_id", "arena_boss")
	stage.add_child(boss)
	boss.call("configure_spawn", {"web": {"role": "boss", "boss_wave": 2}})
	boss.position = Vector3(6, 0, 6)
	var director := DIRECTOR.new()
	director.web = true
	director.wave_pause = 0.2
	stage.add_child(director)
	director.wave_announced.connect(func(wave: int, is_boss: bool) -> void: _announced.append([wave, is_boss]))
	director.arena_cleared.connect(func() -> void: _cleared += 1)
	director.configure(enemies, player)
	director.arm()
	for step in 60:
		await physics_frame
	_check(_announced.is_empty() and _spawned(enemies).is_empty(), "wave 0: nothing starts while a placed infected lives")
	placed.call("take_damage", 99999.0)
	_check(await _wait_for(enemies, 5), "wave 1 spawns 5 after the placed infected die")
	_check(_announced == [[1, false]], "wave 1 is announced before it starts")
	await _kill_all(enemies)
	_check(await _wait_for(enemies, 8), "wave 2 has 7 hungers and the Horde")
	_check(_announced == [[1, false], [2, true]] and _cleared == 0, "the Horde wave is announced as boss, arena not cleared yet")
	await _kill_all(enemies)
	for step in 60:
		await physics_frame
	_check(_cleared == 1 and director.web_wave == 2, "killing the Horde wave clears the arena once")
	director.disarm()
	_check(director.web_wave == -1, "disarm resets the waves")
	stage.queue_free()
	await process_frame
