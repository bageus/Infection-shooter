extends SceneTree
## Spawn waves: config repair, trigger rules, the shared queue and the director.

const CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const QUEUE := preload("res://game/features/spawning/domain/wave_queue.gd")
const DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
const POINT := preload("res://game/features/spawning/public/spawn_point.tscn")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_config()
	_trigger_rules()
	_queue_rules()
	await _director()
	await _burst_spread()
	print("Wave tests: %d failures" % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)


func _config() -> void:
	var clean := CONFIG.sanitize({"enemy": "dragon", "count": 9999, "interval": -4, "rule": "burst", "batch": "x", "trigger": "all"})
	_check(clean["enemy"] == "hunger" and clean["count"] == CONFIG.COUNT_MAX, "bad enemy falls back and count is capped")
	_check(clean["interval"] == CONFIG.INTERVAL_MIN and clean["batch"] == 5, "interval floor and default batch")
	_check(clean["rule"] == "burst" and clean["trigger"] == "all", "valid rule and trigger are kept")
	_check(CONFIG.sanitize("junk") == CONFIG.defaults(), "non-dictionary gives defaults")
	var stats := CONFIG.sanitize({"health": 999, "damage": 10})
	_check(stats["health"] == CONFIG.STAT_MAX and stats["damage"] == CONFIG.STAT_MIN, "health and damage are clamped to 50-200%")
	_check(CONFIG.sanitize({"enemy": "hunger"})["health"] == 100.0, "health and damage default to 100%")
	for id in CONFIG.ENEMIES:
		_check(ResourceLoader.exists(CONFIG.scene_path(id)), "enemy scene exists: " + id)


func _trigger_rules() -> void:
	_check(not QUEUE.trigger_met("any", []), "no linked infected never fires")
	_check(QUEUE.trigger_met("any", [false, true, false]), "any: one death fires")
	_check(not QUEUE.trigger_met("all", [true, false, true]), "all: waits for the last one")
	_check(QUEUE.trigger_met("all", [true, true]), "all: fires when every one is dead")


func _queue_rules() -> void:
	var queue := QUEUE.new()
	_check(queue.activate("a", {"count": 3, "interval": 1.0}), "first activation starts the wave")
	_check(not queue.activate("a", {"count": 3}), "a point fires only once")
	var first := queue.step(0.1, 0, 90, {})
	_check(first.size() == 1 and first[0]["count"] == 1, "stream spawns one at a time")
	_check(queue.step(0.5, 0, 90, {}).is_empty(), "stream waits for the interval")
	_check(queue.step(0.5, 0, 90, {}).size() == 1, "stream spawns again after the interval")
	queue.clear()
	queue.activate("b", {"count": 12, "interval": 1.0, "rule": "burst", "batch": 5})
	_check(queue.step(0.1, 0, 90, {})[0]["count"] == 5, "burst spawns a batch")
	queue.step(1.0, 0, 90, {})
	queue.step(1.0, 0, 90, {})
	_check(queue.pending("b") == 0, "burst ends with the remainder")
	queue.clear()
	queue.activate("c", {"count": 10, "interval": 0.2, "rule": "refill", "batch": 3})
	var spawned := 0
	for tick in 20:
		for order in queue.step(0.3, 0, 90, {"c": spawned}):
			spawned += int(order["count"])
	_check(spawned == 3, "refill stops at the batch size while they live (%d)" % spawned)
	_check(not queue.step(0.3, 0, 90, {"c": 2}).is_empty(), "refill adds one when one dies")
	queue.clear()
	queue.activate("d", {"count": 50, "interval": 0.1, "rule": "burst", "batch": 20})
	_check(queue.step(0.1, 85, 90, {})[0]["count"] == 5, "a wave never exceeds the level cap")
	_check(queue.step(0.5, 90, 90, {}).is_empty(), "no spawn while the level is full")
	queue.clear()
	queue.activate("x", {"count": 30, "interval": 0.1})
	queue.activate("y", {"count": 30, "interval": 0.1})
	var served := {"x": 0, "y": 0}
	for tick in 20:
		for order in queue.step(0.1, 89, 90, {}):
			served[order["id"]] += int(order["count"])
	_check(abs(int(served["x"]) - int(served["y"])) <= 1 and int(served["x"]) > 3, "two points share one free slot in turn %s" % str(served))


func _stage() -> Dictionary:
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
	enemies.name = "Enemies"
	stage.add_child(enemies)
	var player := Node3D.new()
	player.position = Vector3(10, 1, 0)
	stage.add_child(player)
	return {"stage": stage, "enemies": enemies, "player": player}


func _enemy(enemies: Node3D, position: Vector3, point_ids: Array) -> Node3D:
	var enemy := HUNGER.instantiate() as Node3D
	enemy.position = position
	enemy.set_meta(DIRECTOR.TRIGGER_META, point_ids)
	enemies.add_child(enemy)
	return enemy


func _director() -> void:
	var world := _stage()
	var stage: Node3D = world["stage"]
	var enemies: Node3D = world["enemies"]
	var player: Node3D = world["player"]
	var point := POINT.instantiate() as Node3D
	point.set_meta("planning_object_id", "spawn_test")
	stage.add_child(point)
	point.call("configure_spawn", {"enemy": "hunger", "count": 6, "interval": 0.1, "rule": "stream", "health": 150, "damage": 50})
	point.position = Vector3(-6, 0, 0)
	var guards: Array[Node3D] = []
	for index in 3:
		guards.append(_enemy(enemies, Vector3(0, 1, index * 3), ["spawn_test"]))
	var director := DIRECTOR.new()
	stage.add_child(director)
	director.configure(enemies, player)
	director.arm()
	await physics_frame
	await physics_frame
	_check(enemies.get_child_count() == 3 and director.pending_total() == 0, "nothing spawns while the triggers live")
	_check(point.get_children().size() >= 4, "the hole has visuals")
	guards[0].call("take_damage", 9999.0)
	await _frames(24)
	_check(director.has_fired("spawn_test"), "the first death fires the wave")
	guards[1].call("take_damage", 9999.0)
	guards[2].call("take_damage", 9999.0)
	await _frames(90)
	var spawned := _spawned(enemies)
	_check(spawned.size() == 6, "three deaths start one wave of 6, not three (%d)" % spawned.size())
	var at_player := true
	var near_hole := true
	for enemy in spawned:
		at_player = at_player and enemy.get("_target") == player
		near_hole = near_hole and (enemy.get_meta(&"spawn_origin") as Vector3).distance_to(point.global_position) < 2.2
	_check(at_player, "spawned infected hunt the player")
	_check(near_hole, "spawned infected appear beside the hole")
	var spots := {}
	for enemy in spawned:
		var origin: Vector3 = enemy.get_meta(&"spawn_origin")
		spots[Vector2i(roundi(origin.x * 4.0), roundi(origin.z * 4.0))] = true
	_check(spots.size() >= 4, "spawned infected do not stack on one spot")
	_check(spawned.all(func(enemy: Node3D) -> bool: return enemy.call("get_enemy_stats") == {"health": 150.0, "damage": 50.0}), "spawned infected get the hole's health and damage")
	director.disarm()
	await process_frame
	await process_frame
	_check(_spawned(enemies).is_empty(), "disarm removes the spawned infected")
	stage.queue_free()
	await process_frame
	await _cap()


func _spawned(enemies: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for enemy in enemies.get_children():
		if enemy.has_meta(&"spawned_by") and not enemy.is_queued_for_deletion():
			found.append(enemy)
	return found


func _frames(count: int) -> void:
	for step in count:
		await physics_frame


func _cap() -> void:
	var world := _stage()
	var stage: Node3D = world["stage"]
	var enemies: Node3D = world["enemies"]
	var player: Node3D = world["player"]
	for id in ["a", "b"]:
		var point := POINT.instantiate() as Node3D
		point.set_meta("planning_object_id", "spawn_" + id)
		stage.add_child(point)
		point.call("configure_spawn", {"enemy": "hunger", "count": 30, "interval": 0.1, "trigger": "all"})
		point.position = Vector3(-10 if id == "a" else 10, 0, -8)
	var trigger := _enemy(enemies, Vector3(0, 1, 4), ["spawn_a", "spawn_b"])
	var director := DIRECTOR.new()
	director.max_alive = 12
	stage.add_child(director)
	director.configure(enemies, player)
	director.arm()
	trigger.call("take_damage", 9999.0)
	await _frames(120)
	var first := _spawned(enemies)
	_check(first.size() == 12, "two points together stop at the cap of 12 (%d)" % first.size())
	_check(director.alive_count() == 12, "alive count equals the cap")
	_check(director.pending_total() == 48, "the rest of both waves waits in the queue (%d)" % director.pending_total())
	var from_a := 0
	for enemy in first:
		from_a += 1 if enemy.get_meta(&"spawned_by") == "spawn_a" else 0
	_check(absi(from_a - (first.size() - from_a)) <= 2, "both points spawned their share (%d of 12 from a)" % from_a)
	for enemy in first.slice(0, 4):
		enemy.call("take_damage", 9999.0)
	await _frames(60)
	_check(director.alive_count() == 12 and director.pending_total() == 44, "deaths free slots and the queue refills them (%d pending)" % director.pending_total())
	stage.queue_free()
	await process_frame


func _burst_spread() -> void:
	var world := _stage()
	var stage: Node3D = world["stage"]
	var enemies: Node3D = world["enemies"]
	var player: Node3D = world["player"]
	var point := POINT.instantiate() as Node3D
	point.set_meta("planning_object_id", "spawn_burst")
	stage.add_child(point)
	point.call("configure_spawn", {"enemy": "hunger", "count": 10, "interval": 5.0, "rule": "burst", "batch": 10, "trigger": "any"})
	point.position = Vector3(-10, 0, -8)
	var trigger := _enemy(enemies, Vector3(0, 1, 4), ["spawn_burst"])
	var director := DIRECTOR.new()
	stage.add_child(director)
	director.configure(enemies, player)
	director.arm()
	trigger.call("take_damage", 9999.0)
	var most := 0
	var previous := 0
	for step in 40:
		await physics_frame
		var now := _spawned(enemies).size()
		most = maxi(most, now - previous)
		previous = now
	_check(previous == 10, "a burst of 10 still arrives in full (%d)" % previous)
	_check(most <= DIRECTOR.SPAWNS_PER_FRAME, "no more than %d infected appear in one frame (%d)" % [DIRECTOR.SPAWNS_PER_FRAME, most])
	stage.queue_free()
	await process_frame
