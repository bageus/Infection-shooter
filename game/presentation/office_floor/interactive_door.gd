extends Node3D

enum DoorMode { SWING_BIDIRECTIONAL, SWING_ONE_WAY, SLIDING_ELEVATOR }

@export var mode: DoorMode = DoorMode.SWING_BIDIRECTIONAL
@export var trigger_distance: float = 1.45
@export var open_angle_degrees: float = 92.0
@export var open_speed: float = 5.5
@export var close_delay: float = 0.7
@export var one_way_allowed_side: float = 1.0
@export var slide_distance: float = 0.72
@export var elevator_sync_radius: float = 4.0
@export var player_path: NodePath = NodePath("/root/Main/Gameplay/Player")

var _player: Node3D
var _door_parts: Array[Node3D] = []
var _closed_transforms: Array[Transform3D] = []
var _open_amount := 0.0
var _close_timer := 0.0
var _requested_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_player = get_node_or_null(player_path) as Node3D
	if mode == DoorMode.SLIDING_ELEVATOR:
		add_to_group("elevator_door_components")
	_collect_door_parts()
	_disable_static_collision_for_door_parts()


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var wants_open := _requested_open
	_requested_open = false
	var local_player := to_local(_player.global_position)
	var horizontal_distance := Vector2(local_player.x, local_player.z).length()

	if horizontal_distance <= trigger_distance:
		match mode:
			DoorMode.SWING_BIDIRECTIONAL:
				wants_open = true
			DoorMode.SWING_ONE_WAY:
				var side := signf(local_player.z)
				if side == signf(one_way_allowed_side):
					wants_open = true
			DoorMode.SLIDING_ELEVATOR:
				wants_open = true
				_request_nearby_elevator_open()

	if wants_open:
		_close_timer = close_delay
		_open_amount = move_toward(_open_amount, 1.0, open_speed * delta)
	else:
		_close_timer = maxf(0.0, _close_timer - delta)
		if _close_timer <= 0.0:
			_open_amount = move_toward(_open_amount, 0.0, open_speed * delta)

	_apply_door_pose(local_player)


func request_open() -> void:
	_requested_open = true


func _request_nearby_elevator_open() -> void:
	for node in get_tree().get_nodes_in_group("elevator_door_components"):
		if node == self or not node is Node3D:
			continue
		var other := node as Node3D
		if global_position.distance_to(other.global_position) <= elevator_sync_radius and other.has_method("request_open"):
			other.call("request_open")


func _collect_door_parts() -> void:
	var visual := get_node_or_null("Visual")
	if visual == null:
		return
	var candidates: Array[Node3D] = []
	_collect_named_meshes(visual, candidates)
	if candidates.is_empty():
		_collect_all_meshes(visual, candidates)
	if mode == DoorMode.SLIDING_ELEVATOR and candidates.size() > 2:
		candidates = candidates.slice(0, 2)
	elif mode != DoorMode.SLIDING_ELEVATOR and candidates.size() > 1:
		candidates = [candidates[0]]
	for part in candidates:
		_door_parts.append(part)
		_closed_transforms.append(part.transform)


func _collect_named_meshes(node: Node, out: Array[Node3D]) -> void:
	if node is MeshInstance3D:
		var lower := node.name.to_lower()
		if "door" in lower or "leaf" in lower or "panel" in lower:
			out.append(node as Node3D)
	for child in node.get_children():
		_collect_named_meshes(child, out)


func _collect_all_meshes(node: Node, out: Array[Node3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as Node3D)
	for child in node.get_children():
		_collect_all_meshes(child, out)


func _disable_static_collision_for_door_parts() -> void:
	var body := get_node_or_null("Body") as StaticBody3D
	if body == null:
		return
	# Structural collision is generated from the full imported mesh. Door motion
	# must not keep an invisible closed blocker, so disable that aggregate body.
	# Non-door frame collision remains supplied by the visual structural pieces
	# in dedicated scenes where applicable.
	body.collision_layer = 0
	body.collision_mask = 0


func _apply_door_pose(local_player: Vector3) -> void:
	for i in _door_parts.size():
		var part := _door_parts[i]
		if not is_instance_valid(part):
			continue
		var closed := _closed_transforms[i]
		if mode == DoorMode.SLIDING_ELEVATOR:
			var direction := -1.0 if i == 0 else 1.0
			var t := closed
			t.origin.x += direction * slide_distance * _open_amount
			part.transform = t
		else:
			var side := signf(local_player.z)
			if absf(side) < 0.1:
				side = 1.0
			if mode == DoorMode.SWING_ONE_WAY:
				side = signf(one_way_allowed_side)
			var angle := deg_to_rad(open_angle_degrees * side * _open_amount)
			var t := closed
			t.basis = closed.basis.rotated(Vector3.UP, angle)
			part.transform = t
