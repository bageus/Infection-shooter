extends Node

@export var chunk_size := 8.0
@export var active_chunk_radius := 2
@export var collision_chunk_radius := 1
@export var update_interval := 0.15

var player: Node3D
var roots: Array = []
var enabled := true
var _elapsed := 0.0
var _chunks: Dictionary = {}
var _last_center := Vector2i(999999, 999999)

func setup(target: Node3D, managed_roots: Array) -> void:
	player = target
	roots = managed_roots
	rebuild()

func rebuild() -> void:
	_chunks.clear()
	for root in roots:
		if root != null:
			for child in root.get_children():
				if child is Node3D:
					_register_object(child as Node3D)
	_last_center = Vector2i(999999, 999999)
	_update_chunks(true)

func _register_object(object: Node3D) -> void:
	if object == player or object.is_in_group("infected"):
		return
	var key := _chunk_for(object.global_position)
	if not _chunks.has(key):
		_chunks[key] = []
	var bucket: Array = _chunks[key]
	bucket.append(object)
	_chunks[key] = bucket

func _chunk_for(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / chunk_size), floori(position.z / chunk_size))

func _process(delta: float) -> void:
	if not enabled or player == null or not is_instance_valid(player):
		return
	_elapsed += delta
	if _elapsed < update_interval:
		return
	_elapsed = 0.0
	_update_chunks(false)

func _update_chunks(force: bool) -> void:
	var center := _chunk_for(player.global_position)
	if not force and center == _last_center:
		return
	_last_center = center
	for key_variant in _chunks.keys():
		var key: Vector2i = key_variant
		var dx := absi(key.x - center.x)
		var dy := absi(key.y - center.y)
		var render_active := dx <= active_chunk_radius and dy <= active_chunk_radius
		var collision_active := dx <= collision_chunk_radius and dy <= collision_chunk_radius
		var bucket: Array = _chunks[key]
		for object_variant in bucket:
			if not is_instance_valid(object_variant):
				continue
			var object: Node3D = object_variant
			if object == null:
				continue
			object.visible = render_active
			object.process_mode = Node.PROCESS_MODE_INHERIT if render_active else Node.PROCESS_MODE_DISABLED
			_set_collision_enabled(object, collision_active)

func _set_collision_enabled(node: Node, value: bool) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).set_deferred("disabled", not value)
	for child in node.get_children():
		_set_collision_enabled(child, value)

func set_runtime_enabled(value: bool) -> void:
	enabled = value
	if not value:
		for key_variant in _chunks.keys():
			var bucket: Array = _chunks[key_variant]
			for object_variant in bucket:
				if not is_instance_valid(object_variant):
					continue
				var object: Node3D = object_variant
				if object != null:
					object.visible = true
					object.process_mode = Node.PROCESS_MODE_INHERIT
					_set_collision_enabled(object, true)
	else:
		_last_center = Vector2i(999999, 999999)
		_update_chunks(true)
