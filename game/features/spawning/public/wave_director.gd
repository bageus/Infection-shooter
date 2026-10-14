extends Node
## Runs the mission's spawn waves. A spawn point fires once, when the infected
## linked to it die (spawn_config trigger rule); fired waves share one queue and
## never push the living infected past MAX_ALIVE. Spawned infected hunt the player.

const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const WAVE_QUEUE := preload("res://game/features/spawning/domain/wave_queue.gd")
## Meta on a placed infected: Array of spawn point ids whose wave its death can start.
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
var _scenes := {}
var _spawn_index := {}
var _backlog: Array[String] = []
var _wave_clock := 0.0
var _poll_clock := 0.0


func configure(enemies_root: Node3D, player: Node3D) -> void:
	_enemies_root = enemies_root
	_player = player


## Reads the authored map: spawn points and the infected linked to them.
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
		_linked[id] = []
		_spawned[id] = []
		_scenes[id] = load(SPAWN_CONFIG.scene_path(str(node.call("get_spawn_config")["enemy"]))) as PackedScene
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
	_scenes.clear()
	_spawn_index.clear()
	_queue.clear()
	_backlog.clear()
	_armed = false
	_wave_clock = 0.0
	_poll_clock = 0.0


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


## Starts the wave of every point whose linked infected have died.
func check_triggers() -> void:
	for id: String in _points:
		if _queue.has_fired(id) or not is_instance_valid(_points[id]):
			continue
		var dead: Array = []
		for enemy in _linked[id]:
			dead.append(not is_instance_valid(enemy) or bool(enemy.call("is_dead")))
		var config: Dictionary = _points[id].call("get_spawn_config")
		if WAVE_QUEUE.trigger_met(str(config["trigger"]), dead):
			_queue.activate(id, config)


func advance(delta: float) -> void:
	if _queue.total_pending() == 0:
		return
	var own := {}
	for id: String in _spawned:
		_spawned[id] = _spawned[id].filter(func(enemy: Variant) -> bool: return is_instance_valid(enemy) and not bool(enemy.call("is_dead")))
		own[id] = _spawned[id].size() + _backlog.count(id)
	# Infected still waiting in the backlog already hold their slots under the cap.
	for order in _queue.step(delta, alive_count() + _backlog.size(), max_alive, own):
		for step in int(order["count"]):
			_backlog.append(str(order["id"]))


func _drain_backlog() -> void:
	var budget := mini(SPAWNS_PER_FRAME, _backlog.size())
	for step in budget:
		_spawn(_backlog.pop_front(), 1)


func _spawn(point_id: String, count: int) -> void:
	var point: Node3D = _points.get(point_id)
	var packed: PackedScene = _scenes.get(point_id)
	if not is_instance_valid(point) or packed == null:
		return
	for step in count:
		var index: int = _spawn_index.get(point_id, 0)
		_spawn_index[point_id] = index + 1
		var enemy := packed.instantiate() as Node3D
		var ground: Vector3 = point.call("spawn_position", index)
		var yaw := 0.0
		if is_instance_valid(_player):
			var toward := _player.global_position - ground
			yaw = atan2(-toward.x, -toward.z)
		# Placed before it enters the tree so its blood trail starts at the hole.
		enemy.transform = Transform3D(Basis(Vector3.UP, yaw), _enemies_root.to_local(ground + Vector3(0.0, _standing_height(enemy), 0.0)))
		enemy.set_meta(&"spawned_by", point_id)
		enemy.set_meta(&"spawn_origin", ground)
		_enemies_root.add_child(enemy)
		if enemy.has_method("set_target"):
			enemy.call("set_target", _player)
		_spawned[point_id].append(enemy)


# Tall infected (capsule up to 2.9 m) must start above the floor, not inside it.
func _standing_height(enemy: Node) -> float:
	var shape_node := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null and shape_node.shape is CapsuleShape3D:
		return maxf(1.0, (shape_node.shape as CapsuleShape3D).height * 0.5 + 0.1)
	return 1.0
