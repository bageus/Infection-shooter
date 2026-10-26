extends Node
## Runs the mission's spawn waves. A spawn point has one or more queues; each queue
## fires once, either when the infected linked to it die (spawn_config trigger rule)
## or a set time after the previous queue started. Fired queues share one wave queue
## and never push the living infected past MAX_ALIVE. Spawned infected hunt the player.

const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const WAVE_QUEUE := preload("res://game/features/spawning/domain/wave_queue.gd")
## Meta on a placed infected: Array of link keys (spawn_config.link_key) whose queue its death can start.
const TRIGGER_META := &"spawn_triggers"
const POINT_GROUP := &"enemy_spawn_points"
## Group of living infected, owned by features.infected.
const ALIVE_GROUP := &"infected_alive"
const WAVE_STEP := 0.1
const TRIGGER_POLL := 0.25
## Infected instantiated per physics frame; a big batch is spread over several frames.
const SPAWNS_PER_FRAME := 3

var max_alive := WAVE_QUEUE.MAX_ALIVE

var _enemies_root: Node3D
var _player: Node3D
var _queue := WAVE_QUEUE.new()
var _armed := false
var _points := {}
var _linked := {}
var _spawned := {}
var _queues := {}
var _fired_at := {}
var _scenes := {}
var _spawn_index := {}
var _elapsed := 0.0
var _backlog: Array[Dictionary] = []
var _wave_clock := 0.0
var _poll_clock := 0.0


func configure(enemies_root: Node3D, player: Node3D) -> void:
	_enemies_root = enemies_root
	_player = player


## Reads the authored map: spawn points, their queues and the infected linked to them.
func arm() -> void:
	disarm()
	_armed = true
	for node in get_tree().get_nodes_in_group(POINT_GROUP):
		if not node is Node3D or node.is_queued_for_deletion() or node.has_meta(&"planning_preview"):
			continue
		var id := str(node.get_meta(&"planning_object_id", ""))
		if id.is_empty():
			continue
		_points[id] = node
		var queues: Array = node.call("get_spawn_config")["queues"]
		for index in queues.size():
			var key := SPAWN_CONFIG.link_key(id, index)
			_queues[key] = {"point": id, "index": index, "config": queues[index]}
			_linked[key] = []
			_spawned[key] = []
	for enemy in _enemies_root.get_children():
		var ids: Variant = enemy.get_meta(TRIGGER_META, [])
		if not ids is Array:
			continue
		for id in ids:
			if _linked.has(str(id)):
				_linked[str(id)].append(enemy)


## Drops pending waves and removes what they spawned (planner entered or mission restarted).
func disarm() -> void:
	for id in _spawned:
		for enemy in _spawned[id]:
			if is_instance_valid(enemy):
				enemy.queue_free()
	_points.clear()
	_linked.clear()
	_spawned.clear()
	_queues.clear()
	_fired_at.clear()
	_scenes.clear()
	_spawn_index.clear()
	_queue.clear()
	_backlog.clear()
	_armed = false
	_wave_clock = 0.0
	_poll_clock = 0.0
	_elapsed = 0.0


func is_armed() -> bool:
	return _armed


func pending_total() -> int:
	return _queue.total_pending() + _backlog.size()


func has_fired(point_id: String) -> bool:
	return _queue.has_fired(point_id)


func alive_count() -> int:
	return get_tree().get_nodes_in_group(ALIVE_GROUP).size()


func _physics_process(delta: float) -> void:
	if not _armed:
		arm()
	_poll_clock += delta
	if _poll_clock >= TRIGGER_POLL:
		_poll_clock = 0.0
		check_triggers()
	_wave_clock += delta
	if _wave_clock >= WAVE_STEP:
		advance(_wave_clock)
		_wave_clock = 0.0
	_drain_backlog()


## Starts every queue whose linked infected have died.
func check_triggers() -> void:
	for key: String in _queues:
		var queue: Dictionary = _queues[key]
		var config: Dictionary = queue["config"]
		if _queue.has_fired(key) or not is_instance_valid(_points[queue["point"]]):
			continue
		if int(queue["index"]) > 0 and str(config["start"]) == "time":
			continue
		var dead: Array = []
		for enemy in _linked[key]:
			dead.append(not is_instance_valid(enemy) or bool(enemy.call("is_dead")))
		if WAVE_QUEUE.trigger_met(str(config["trigger"]), dead):
			_fire(key)


## Starts every timed queue whose predecessor started long enough ago.
func _check_delays() -> void:
	for key: String in _queues:
		var queue: Dictionary = _queues[key]
		var config: Dictionary = queue["config"]
		var index := int(queue["index"])
		if index == 0 or str(config["start"]) != "time" or _queue.has_fired(key) or not is_instance_valid(_points[queue["point"]]):
			continue
		var previous := SPAWN_CONFIG.link_key(str(queue["point"]), index - 1)
		if _fired_at.has(previous) and _elapsed >= float(_fired_at[previous]) + float(config["delay"]):
			_fire(key)


func _fire(key: String) -> void:
	if _queue.activate(key, _queues[key]["config"]):
		_fired_at[key] = _elapsed


func advance(delta: float) -> void:
	_elapsed += delta
	_check_delays()
	if _queue.total_pending() == 0:
		return
	var own := {}
	for key: String in _spawned:
		_spawned[key] = _spawned[key].filter(func(enemy: Variant) -> bool: return is_instance_valid(enemy) and not bool(enemy.call("is_dead")))
		own[key] = _spawned[key].size() + _backlog.filter(func(order: Dictionary) -> bool: return order["key"] == key).size()
	# Infected still waiting in the backlog already hold their slots under the cap.
	for order in _queue.step(delta, alive_count() + _backlog.size(), max_alive, own):
		for kind: String in order["enemies"]:
			_backlog.append({"key": str(order["id"]), "enemy": kind})


func _drain_backlog() -> void:
	var budget := mini(SPAWNS_PER_FRAME, _backlog.size())
	for step in budget:
		var order: Dictionary = _backlog.pop_front()
		_spawn(str(order["key"]), str(order["enemy"]))


func _spawn(key: String, enemy_id: String) -> void:
	var queue: Dictionary = _queues.get(key, {})
	var point: Node3D = _points.get(queue.get("point", ""))
	if queue.is_empty() or not is_instance_valid(point):
		return
	if not _scenes.has(enemy_id):
		_scenes[enemy_id] = load(SPAWN_CONFIG.scene_path(enemy_id)) as PackedScene
	var packed: PackedScene = _scenes[enemy_id]
	if packed == null:
		return
	var point_id: String = queue["point"]
	var config: Dictionary = queue["config"]
	var index: int = _spawn_index.get(point_id, 0)
	_spawn_index[point_id] = index + 1
	var enemy := packed.instantiate() as Node3D
	if enemy.has_method("configure_stats"):
		enemy.call("configure_stats", {"health": config["health"], "damage": config["damage"]})
	var ground: Vector3 = point.call("spawn_position", index)
	var yaw := 0.0
	if is_instance_valid(_player):
		var toward := _player.global_position - ground
		yaw = atan2(-toward.x, -toward.z)
	# Placed before it enters the tree so its blood trail starts at the hole.
	enemy.transform = Transform3D(Basis(Vector3.UP, yaw), _enemies_root.to_local(ground + Vector3(0.0, _standing_height(enemy), 0.0)))
	enemy.set_meta(&"spawned_by", point_id)
	enemy.set_meta(&"spawned_queue", int(queue["index"]))
	enemy.set_meta(&"spawn_origin", ground)
	_enemies_root.add_child(enemy)
	if enemy.has_method("set_target"):
		enemy.call("set_target", _player)
	_spawned[key].append(enemy)


# Tall infected (capsule up to 2.9 m) must start above the floor, not inside it.
func _standing_height(enemy: Node) -> float:
	var shape_node := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		return maxf(1.0, (shape_node.shape as CapsuleShape3D).height * 0.5 + 0.1)
	return 1.0
