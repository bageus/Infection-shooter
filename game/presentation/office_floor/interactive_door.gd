extends Node3D

enum DoorMode { SWING_BIDIRECTIONAL, SWING_ONE_WAY, SLIDING_ELEVATOR, GLASS_SWING }

@export var mode: DoorMode = DoorMode.SWING_BIDIRECTIONAL
@export var trigger_distance: float = 1.45
@export var open_angle_degrees: float = 92.0
@export var open_speed: float = 5.5
@export var close_delay: float = 0.7
@export var one_way_allowed_side: float = 1.0
@export var slide_distance: float = 0.72
@export var elevator_sync_radius: float = 4.0
@export var player_path: NodePath

var _player: Node3D
var _door_parts: Array[Node3D] = []
var _left_slide_parts: Array[Node3D] = []
var _right_slide_parts: Array[Node3D] = []
var _closed_transforms: Array[Transform3D] = []
var _open_amount := 0.0
var _close_timer := 0.0
var _requested_open := false
var _swing_side := 0.0
var _door_recess_nodes: Array[Node3D] = []
var _glass_hinge: Node3D
var _glass_hinge_closed := Transform3D.IDENTITY
var _elevator_lights: Array[Node3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("interactive_doors")
	_player = get_node_or_null(player_path) as Node3D if not player_path.is_empty() else null
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		var scene := get_tree().current_scene
		if scene != null:
			_player = scene.get_node_or_null("Gameplay/Player") as Node3D
	if mode == DoorMode.SLIDING_ELEVATOR:
		add_to_group("elevator_door_components")
	_collect_door_parts()


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
				if _open_amount <= 0.02 and _swing_side == 0.0:
					_swing_side = _player_side(local_player)
			DoorMode.SWING_ONE_WAY:
				var side := signf(local_player.z)
				if side == signf(one_way_allowed_side):
					wants_open = true
					if _open_amount <= 0.02:
						_swing_side = signf(one_way_allowed_side)
			DoorMode.SLIDING_ELEVATOR, DoorMode.GLASS_SWING:
				wants_open = true
				if mode == DoorMode.SLIDING_ELEVATOR:
					_request_nearby_elevator_open()

	if wants_open:
		_close_timer = close_delay
		_open_amount = move_toward(_open_amount, 1.0, open_speed * delta)
	else:
		_close_timer = maxf(0.0, _close_timer - delta)
		if _close_timer <= 0.0:
			_open_amount = move_toward(_open_amount, 0.0, open_speed * delta)
			if _open_amount <= 0.001:
				_swing_side = 0.0

	_apply_door_pose(local_player)
	if mode == DoorMode.GLASS_SWING and _glass_hinge != null:
		var swing_side := _swing_side
		if swing_side == 0.0:
			swing_side = _player_side(local_player)
			_swing_side = swing_side
		var hinge_transform := _glass_hinge_closed
		hinge_transform.basis = _glass_hinge_closed.basis.rotated(Vector3.UP, deg_to_rad(open_angle_degrees * swing_side * _open_amount))
		_glass_hinge.transform = hinge_transform
	for recess in _door_recess_nodes:
		if is_instance_valid(recess):
			recess.visible = _open_amount <= 0.001
	for light_node in _elevator_lights:
		if is_instance_valid(light_node):
			_set_light_state(light_node, _open_amount >= 0.98)


func is_open_for_exploration() -> bool:
	return _open_amount >= 0.12


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
	var visual := get_parent().get_node_or_null("Visual")
	if visual == null:
		return
	if mode == DoorMode.SLIDING_ELEVATOR:
		_collect_elevator_parts(visual)
		_collect_named_nodes(visual, "doorrecess", _door_recess_nodes)
		_collect_elevator_lights(visual)
	elif mode == DoorMode.GLASS_SWING:
		_build_glass_hinge(visual)
	else:
		var pivot: Node3D
		if mode == DoorMode.SWING_ONE_WAY:
			pivot = _find_exact_named_node(visual, "doorpivot.001")
			if pivot == null:
				pivot = _find_exact_named_node(visual, "doorpivot")
		else:
			pivot = _find_exact_named_node(visual, "doorpivot")
		if pivot != null:
			_door_parts.append(pivot)
			_closed_transforms.append(pivot.transform)
		else:
			var candidates: Array[Node3D] = []
			_collect_named_meshes(visual, candidates)
			if not candidates.is_empty():
				_door_parts.append(candidates[0])
				_closed_transforms.append(candidates[0].transform)


func _collect_elevator_parts(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D:
			var n := child as Node3D
			var lower := n.name.to_lower()
			if "innerdoor_left" in lower or "innetdoor_left" in lower or "door_left" in lower:
				_left_slide_parts.append(n)
			elif "innerdoor_right" in lower or "innetdoor_right" in lower or "door_right" in lower:
				_right_slide_parts.append(n)
		_collect_elevator_parts(child)
	for part in _left_slide_parts:
		if not _door_parts.has(part):
			_door_parts.append(part)
			_closed_transforms.append(part.transform)
	for part in _right_slide_parts:
		if not _door_parts.has(part):
			_door_parts.append(part)
			_closed_transforms.append(part.transform)


func _collect_elevator_lights(node: Node) -> void:
	if node is Node3D:
		var lower := node.name.to_lower()
		if "light" in lower or "lamp" in lower or "indicator" in lower:
			_elevator_lights.append(node as Node3D)
	for child in node.get_children():
		_collect_elevator_lights(child)


func _set_light_state(node: Node3D, enabled: bool) -> void:
	if node is Light3D:
		(node as Light3D).visible = enabled
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_active_material(surface)
			if material is StandardMaterial3D:
				var material_copy := material.duplicate() as StandardMaterial3D
				material_copy.emission_enabled = enabled
				if enabled:
					material_copy.emission = Color(1.0, 0.78, 0.28)
					material_copy.emission_energy_multiplier = 4.0
				mesh_instance.set_surface_override_material(surface, material_copy)
	for child in node.get_children():
		if child is Node3D:
			_set_light_state(child as Node3D, enabled)


func _build_glass_hinge(visual: Node3D) -> void:
	var glass := _find_exact_named_node(visual, "doorglass")
	if glass == null:
		return
	_glass_hinge = Node3D.new()
	_glass_hinge.name = "RuntimeDoorPivot"
	visual.add_child(_glass_hinge)
	var bounds := _combined_parts_aabb(visual, ["doorglass", "doorhandle", "doortoppanel"])
	var hinge_local := Vector3(bounds.position.x, bounds.position.y, bounds.get_center().z)
	_glass_hinge.position = hinge_local
	_glass_hinge_closed = _glass_hinge.transform
	for wanted in ["doorglass", "doorhandle", "doortoppanel"]:
		var part := _find_exact_named_node(visual, wanted)
		if part != null:
			part.reparent(_glass_hinge, true)


func _combined_parts_aabb(root: Node3D, names: Array[String]) -> AABB:
	var result := AABB()
	var found := false
	for wanted in names:
		var part := _find_exact_named_node(root, wanted)
		if part is MeshInstance3D:
			var mesh_part := part as MeshInstance3D
			var local_transform: Transform3D = root.global_transform.affine_inverse() * mesh_part.global_transform
			var part_aabb: AABB = local_transform * mesh_part.get_aabb()
			result = part_aabb if not found else result.merge(part_aabb)
			found = true
	return result


func _collect_named_nodes(node: Node, token: String, out: Array[Node3D]) -> void:
	if node is Node3D and token in node.name.to_lower():
		out.append(node as Node3D)
	for child in node.get_children():
		_collect_named_nodes(child, token, out)


func _find_exact_named_node(node: Node, wanted: String) -> Node3D:
	if node.name.to_lower() == wanted.to_lower():
		return node as Node3D if node is Node3D else null
	for child in node.get_children():
		var found := _find_exact_named_node(child, wanted)
		if found != null:
			return found
	return null


func _player_side(local_player: Vector3) -> float:
	var side := signf(local_player.z)
	return 1.0 if absf(side) < 0.1 else side


func _find_named_node(node: Node, names: Array[String]) -> Node3D:
	var lower := node.name.to_lower()
	for wanted in names:
		if lower == wanted or wanted in lower:
			return node as Node3D if node is Node3D else null
	for child in node.get_children():
		var found := _find_named_node(child, names)
		if found != null:
			return found
	return null


func _collect_named_meshes(node: Node, out: Array[Node3D]) -> void:
	if node is MeshInstance3D:
		var lower := node.name.to_lower()
		if "door" in lower or "leaf" in lower or "panel" in lower:
			out.append(node as Node3D)
	for child in node.get_children():
		_collect_named_meshes(child, out)


func _apply_door_pose(local_player: Vector3) -> void:
	for i in _door_parts.size():
		var part := _door_parts[i]
		if not is_instance_valid(part):
			continue
		var closed := _closed_transforms[i]
		if mode == DoorMode.SLIDING_ELEVATOR:
			var direction := -1.0 if _left_slide_parts.has(part) else 1.0
			var t := closed
			t.origin.x += direction * slide_distance * _open_amount
			part.transform = t
		elif mode == DoorMode.GLASS_SWING:
			pass
		else:
			var side := _swing_side
			if side == 0.0:
				side = signf(one_way_allowed_side) if mode == DoorMode.SWING_ONE_WAY else _player_side(local_player)
			var angle := deg_to_rad(open_angle_degrees * side * _open_amount)
			var t := closed
			t.basis = closed.basis.rotated(Vector3.UP, angle)
			part.transform = t
