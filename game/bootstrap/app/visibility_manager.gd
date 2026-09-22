extends Node

@export var visible_radius := 22.0
@export var hysteresis := 5.0
@export var update_interval := 0.20
@export var max_updates_per_tick := 160

var player: Node3D
var roots: Array[Node] = []
var _objects: Array[Node3D] = []
var _cursor := 0
var _elapsed := 0.0
var enabled := true

func setup(target: Node3D, managed_roots: Array[Node]) -> void:
	player = target
	roots = managed_roots
	rebuild()

func rebuild() -> void:
	_objects.clear()
	for root in roots:
		if root != null:
			_collect_runtime_objects(root)
	_cursor = 0

func _collect_runtime_objects(root: Node) -> void:
	for child in root.get_children():
		if child is Node3D:
			var object := child as Node3D
			if object == player or object.is_in_group("infected"):
				continue
			_objects.append(object)
		else:
			_collect_runtime_objects(child)

func _process(delta: float) -> void:
	if not enabled or player == null or not is_instance_valid(player):
		return
	_elapsed += delta
	if _elapsed < update_interval:
		return
	_elapsed = 0.0
	if _objects.is_empty():
		return
	var count := mini(max_updates_per_tick, _objects.size())
	for i in count:
		if _cursor >= _objects.size():
			_cursor = 0
		var object := _objects[_cursor]
		_cursor += 1
		if not is_instance_valid(object):
			continue
		var delta_pos := object.global_position - player.global_position
		var distance_sq := delta_pos.x * delta_pos.x + delta_pos.z * delta_pos.z
		var currently_visible := object.visible
		var limit := visible_radius + (hysteresis if currently_visible else 0.0)
		var should_show := distance_sq <= limit * limit
		if currently_visible != should_show:
			object.visible = should_show
			object.process_mode = Node.PROCESS_MODE_INHERIT if should_show else Node.PROCESS_MODE_DISABLED

func set_runtime_enabled(value: bool) -> void:
	enabled = value
	for object in _objects:
		if is_instance_valid(object):
			object.visible = true
			object.process_mode = Node.PROCESS_MODE_INHERIT
