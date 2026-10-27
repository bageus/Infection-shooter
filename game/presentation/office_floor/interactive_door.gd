extends Node3D

enum DoorMode { SWING_BIDIRECTIONAL, SWING_ONE_WAY, SLIDING_ELEVATOR, GLASS_SWING }

@export var mode: DoorMode = DoorMode.SWING_BIDIRECTIONAL
@export var trigger_distance: float = 1.45
@export var open_angle_degrees: float = 92.0
@export var open_speed: float = 1.65
@export var close_delay: float = 0.7
@export var one_way_allowed_side: float = 1.0
@export var slide_distance: float = 0.72
@export var elevator_sync_radius: float = 4.0
@export var requires_emergency_key := false
# Sealed for good: never opens, not even with the emergency key or from the exit side.
@export var permanently_locked := false

# Planner lock setting, in menu order; saved per door in the layout.
const LOCK_OPEN := &"open"
const LOCK_KEY := &"key"
const LOCK_SEALED := &"sealed"
const LOCK_STATES := [LOCK_OPEN, LOCK_KEY, LOCK_SEALED]

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
var _glass_body: StaticBody3D
var _glass_body_closed := Transform3D.IDENTITY
var _glass_hinge_root_closed := Transform3D.IDENTITY
var _elevator_lights: Array[Node3D] = []
var _indicator_glow: OmniLight3D
var _fallback_leaf_collisions: Array[CollisionShape3D] = []
var _key_hint: Node3D
const BUDGET_LIGHT := preload("res://game/presentation/office_floor/budget_omni_light.gd")
const PRESENCE := preload("res://game/presentation/office_floor/door_presence.gd")
const RUNTIME_CACHE := preload("res://game/presentation/office_floor/door_runtime_cache.gd")
var _runtime_cache := RUNTIME_CACHE.new()
var _presence: Area3D
var _elevator_neighbors: Array[WeakRef] = []
var _impact_pool: Node
var _leaf_surfaces: Dictionary = {}
var _pose_ready := false
var _locked_cue_armed := true
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const BADGE := preload("res://game/core/world_badge/public/world_badge.gd")
const LOCKED_ICON := preload("res://assets/interface/icon/locked_door.png")
const LOCKED_TINT := Color("dcae4a")
# Badge centre height in the door's local space, and its size next to the old one.
const LOCK_ICON_HEIGHT := 1.1
const LOCK_ICON_SCALE := 0.8
# Beyond this distance the next approach plays the locked cue again.
const LOCKED_CUE_REARM_DISTANCE := 0.5


# Moving leaf colliders and their render receivers share the existing surface contract.
func configure_world(_container: Node3D, impacts: Node) -> void:
	_impact_pool = impacts
	if is_instance_valid(impacts):
		for body: Node3D in _leaf_surfaces:
			impacts.call("register_surface", body, _leaf_surfaces[body])


func _register_leaf(body: Node3D, visual: Node3D) -> void:
	_leaf_surfaces[body] = visual
	if is_instance_valid(_impact_pool):
		_impact_pool.call("register_surface", body, visual)


# Public structural scene wiring v1.
func configure_player(actor: Node3D) -> void:
	_player = actor


func _enter_tree() -> void:
	_runtime_cache.bind(self, mode == DoorMode.GLASS_SWING)
	if mode == DoorMode.SLIDING_ELEVATOR:
		call_deferred("_bind_elevator_neighbors")


func _exit_tree() -> void:
	_runtime_cache.clear()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("interactive_doors")
	if mode == DoorMode.SLIDING_ELEVATOR:
		add_to_group("elevator_door_components")
	_collect_door_parts()
	_apply_lock_visuals()


# Planner setting: open, closed (the emergency key opens it) or sealed for good.
func get_lock_state() -> StringName:
	if permanently_locked:
		return LOCK_SEALED
	return LOCK_KEY if requires_emergency_key else LOCK_OPEN


func configure_lock_state(state: StringName) -> void:
	requires_emergency_key = state != LOCK_OPEN
	permanently_locked = state == LOCK_SEALED
	if is_node_ready():
		_apply_lock_visuals()


func configure_one_way(one_way: bool) -> void: mode = DoorMode.SWING_ONE_WAY if one_way else DoorMode.SWING_BIDIRECTIONAL


# Elevator doors are not locked; the planner leaves them out of the setting.
func is_lockable() -> bool:
	return mode != DoorMode.SLIDING_ELEVATOR


func _apply_lock_visuals() -> void:
	if requires_emergency_key and _key_hint == null:
		# Locked-door icon in the HUD style, gold like the emergency key cell.
		_key_hint = BADGE.icon(LOCKED_ICON, Rect2(), LOCKED_TINT, LOCK_ICON_HEIGHT)
		_key_hint.name = "LockedDoorIcon"
		_key_hint.scale = Vector3.ONE * LOCK_ICON_SCALE
		add_child(_key_hint)
	if requires_emergency_key and _presence == null:
		_presence = PRESENCE.new()
		add_child(_presence)
	if _key_hint != null:
		_key_hint.visible = requires_emergency_key


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var local_player := to_local(_player.global_position)
	if mode == DoorMode.GLASS_SWING:
		local_player = _runtime_cache.local_player(self, _player.global_position, true)
		_refresh_glass_collision()
	# Keep the cheap proximity check every tick: a teleport or fast approach
	# must open immediately, while animation/delay/remote requests always run.
	var idle_distance := maxf(3.0, trigger_distance + LOCKED_CUE_REARM_DISTANCE)
	if _pose_ready and _open_amount == 0.0 and _close_timer <= 0.0 and not _requested_open and Vector2(local_player.x, local_player.z).length_squared() > idle_distance * idle_distance:
		if _key_hint != null and _key_hint.visible:
			_key_hint.hide()
		_locked_cue_armed = true
		_swing_side = 0.0
		if mode == DoorMode.GLASS_SWING and _glass_hinge != null:
			_swing_side = _player_side(local_player)
		return
	var wants_open := _requested_open and not requires_emergency_key
	_requested_open = false
	var horizontal_distance := Vector2(local_player.x, local_player.z).length()
	var emergency_exit_side := signf(local_player.z) == signf(one_way_allowed_side)
	var has_emergency_key := requires_emergency_key and _player.has_method("has_emergency_key") and bool(_player.call("has_emergency_key"))
	if _key_hint != null:
		_key_hint.visible = requires_emergency_key and horizontal_distance < 3.0 and (permanently_locked or (not emergency_exit_side and not has_emergency_key))
	var blocked := permanently_locked or (requires_emergency_key and not emergency_exit_side and not has_emergency_key)
	if horizontal_distance > trigger_distance + LOCKED_CUE_REARM_DISTANCE:
		_locked_cue_armed = true

	if horizontal_distance <= trigger_distance:
		if blocked:
			_announce_locked()
		else:
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

	if requires_emergency_key and _open_amount > 0.04 and _someone_in_doorway():
		wants_open = true
	var before := _open_amount
	if wants_open:
		_close_timer = close_delay
		_open_amount = move_toward(_open_amount, 1.0, open_speed * delta)
	else:
		_close_timer = maxf(0.0, _close_timer - delta)
		if _close_timer <= 0.0:
			_open_amount = move_toward(_open_amount, 0.0, open_speed * delta)
			if _open_amount <= 0.001:
				_swing_side = 0.0

	_play_door_sound(before, _open_amount)
	if mode == DoorMode.GLASS_SWING and _glass_hinge != null and _swing_side == 0.0:
		_swing_side = _player_side(local_player)
	if before != _open_amount or not _pose_ready:
		_update_door_visuals(local_player)
		_pose_ready = true


# One rattle per approach: the cue re-arms only after the player walks away.
func _announce_locked() -> void:
	if not _locked_cue_armed:
		return
	_locked_cue_armed = false
	SFX.play_ui(self, &"door_locked")


func _refresh_glass_collision() -> void:
	_runtime_cache.refresh_glass_collision()


func _update_door_visuals(local_player: Vector3) -> void:
	_apply_door_pose(local_player)
	for collision in _fallback_leaf_collisions:
		var should_disable := _open_amount >= 0.6
		if collision.disabled != should_disable:
			collision.set_deferred("disabled", should_disable)
	if mode == DoorMode.GLASS_SWING and _glass_hinge != null:
		var swing_side := _swing_side
		if swing_side == 0.0:
			swing_side = _player_side(local_player)
			_swing_side = swing_side
		var hinge_transform := _glass_hinge_closed
		var eased := _open_amount * _open_amount * (3.0 - 2.0 * _open_amount)
		hinge_transform.basis = _glass_hinge_closed.basis.rotated(Vector3.UP, deg_to_rad(open_angle_degrees * swing_side * eased))
		_glass_hinge.transform = hinge_transform
		if is_instance_valid(_glass_body):
			var root_space := (get_parent() as Node3D).global_transform.affine_inverse() * _glass_hinge.global_transform
			_glass_body.transform = root_space * _glass_hinge_root_closed.affine_inverse() * _glass_body_closed
	for recess in _door_recess_nodes:
		if is_instance_valid(recess):
			recess.visible = _open_amount <= 0.001
	# Elevator lights switch only when the open/shut state changes, not every
	# physics frame (each switch rebuilds their materials).
	var lights_on := _open_amount >= 0.98
	if lights_on != _lights_on:
		_lights_on = lights_on
		for light_node in _elevator_lights:
			if is_instance_valid(light_node):
				_set_light_state(light_node, lights_on)
		if is_instance_valid(_indicator_glow):
			_indicator_glow.set_wanted(lights_on)


# Opening starts from shut; swing doors thud when they shut, the elevator
# motor runs as soon as the doors start closing (ADR-0018).
func _play_door_sound(before: float, after: float) -> void:
	var opening := before <= 0.001 and after > 0.001
	var closing := false
	if mode == DoorMode.SLIDING_ELEVATOR:
		closing = before >= 0.999 and after < 0.999
	else:
		closing = before > 0.001 and after <= 0.001
	if not opening and not closing:
		return
	var kind := "door"
	match mode:
		DoorMode.SLIDING_ELEVATOR:
			kind = "elevator"
		DoorMode.GLASS_SWING:
			kind = "glass_door"
		_:
			if requires_emergency_key:
				kind = "metal_door"
	SFX.play(self, StringName(kind + ("_open" if opening else "_close")))


func is_open_for_exploration() -> bool:
	return _open_amount >= 0.12


func request_open() -> void:
	if not requires_emergency_key:
		_requested_open = true


func _someone_in_doorway() -> bool:
	return _presence != null and _presence.call("occupied", self)


func _remember_elevator(other: Node3D) -> void:
	for reference in _elevator_neighbors:
		if reference.get_ref() == other:
			return
	_elevator_neighbors.append(weakref(other))


func _bind_elevator_neighbors() -> void:
	if not is_inside_tree():
		return
	# Discover this module's components once, then bind later additions reciprocally.
	for node in get_tree().get_nodes_in_group("elevator_door_components"):
		if node != self and node is Node3D and node.has_method("_remember_elevator"):
			_remember_elevator(node)
			node.call("_remember_elevator", self)


func _request_nearby_elevator_open() -> void:
	for i in range(_elevator_neighbors.size() - 1, -1, -1):
		var other := _elevator_neighbors[i].get_ref() as Node3D
		if other == null or not other.is_inside_tree():
			_elevator_neighbors.remove_at(i)
			continue
		if other.is_in_group("elevator_door_components") and global_position.distance_to(other.global_position) <= elevator_sync_radius:
			other.call("request_open")


func _collect_door_parts() -> void:
	var visual := get_parent().get_node_or_null("Visual")
	if visual == null:
		return
	if mode == DoorMode.SLIDING_ELEVATOR:
		_collect_elevator_parts(visual)
		_collect_named_nodes(visual, "doorrecess", _door_recess_nodes)
		_collect_elevator_lights(visual)
		_add_indicator_glow()
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
			_add_swing_leaf_collision(pivot)
		else:
			var candidates: Array[Node3D] = []
			_collect_named_meshes(visual, candidates)
			if not candidates.is_empty():
				_door_parts.append(candidates[0])
				_closed_transforms.append(candidates[0].transform)
				_add_swing_leaf_collision(candidates[0])


func _add_swing_leaf_collision(part: Node3D) -> void:
	var leaves: Array[MeshInstance3D] = []
	_collect_leaf_meshes(part, leaves)
	for leaf in leaves:
		var body := StaticBody3D.new()
		body.name = "MovingDoorBody"
		part.add_child(body)
		_register_leaf(body, leaf)
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var bounds := leaf.get_aabb()
		box.size = bounds.size
		collision.shape = box
		body.add_child(collision)
		var mesh_to_body := body.global_transform.affine_inverse() * leaf.global_transform
		collision.transform = mesh_to_body
		collision.position += mesh_to_body.basis * bounds.get_center()
		if "doorhandle" in leaf.name.to_lower():
			_fallback_leaf_collisions.append(collision)


func _collect_leaf_meshes(node: Node, leaves: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and ("doorleaf" in node.name.to_lower() or "door_leaf" in node.name.to_lower() or "doorhandle" in node.name.to_lower()):
		leaves.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_leaf_meshes(child, leaves)


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
			_add_elevator_leaf_collision(part)
	for part in _right_slide_parts:
		if not _door_parts.has(part):
			_door_parts.append(part)
			_closed_transforms.append(part.transform)
			_add_elevator_leaf_collision(part)


func _add_elevator_leaf_collision(part: Node3D) -> void:
	if not part is MeshInstance3D:
		return
	var mesh := part as MeshInstance3D
	if mesh.mesh == null:
		return
	var body := StaticBody3D.new()
	body.name = "MovingLeafBody"
	part.add_child(body)
	_register_leaf(body, mesh)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var bounds := mesh.get_aabb()
	box.size = Vector3(maxf(bounds.size.x, 0.02), maxf(bounds.size.y, 0.02), maxf(bounds.size.z, 0.02))
	collision.shape = box
	collision.position = bounds.get_center()
	body.add_child(collision)


var _lights_on := true # first frame applies the real state
var _light_material_cache: Dictionary = {}


func _collect_elevator_lights(node: Node) -> void:
	if node is Node3D:
		var lower := node.name.to_lower()
		if "light" in lower or "lamp" in lower or "indicator" in lower:
			_elevator_lights.append(node as Node3D)
	for child in node.get_children():
		_collect_elevator_lights(child)


# The lamp above the doors really lights the lobby while the doors stand open.
func _add_indicator_glow() -> void:
	for node in _elevator_lights:
		if node is MeshInstance3D and node.name.to_lower().contains("indicator"):
			_indicator_glow = BUDGET_LIGHT.create(Color(1.0, 0.78, 0.4), 1.6, 3.0)
			_indicator_glow.position = Vector3(0.0, -0.3, -0.45)
			_indicator_glow.set_wanted(false)
			node.add_child(_indicator_glow)
			return


# Collected light nodes include their own descendants, so no recursion here.
func _set_light_state(node: Node3D, enabled: bool) -> void:
	if node is Light3D:
		(node as Light3D).visible = enabled
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var lens := _lens_surface(mesh_instance)
		for surface in mesh_instance.get_surface_override_material_count():
			if surface != lens:
				continue
			var pair: Array = _light_materials(mesh_instance, surface)
			if not pair.is_empty():
				mesh_instance.set_surface_override_material(surface, pair[1] if enabled else pair[0])


# The lens is the smallest surface of an indicator housing; the rest is the frame.
func _lens_surface(mesh_instance: MeshInstance3D) -> int:
	var best := -1
	var best_volume := INF
	var mesh := mesh_instance.mesh
	if mesh == null:
		return best
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var low := vertices[0]
		var high := vertices[0]
		for vertex in vertices:
			low = low.min(vertex)
			high = high.max(vertex)
		var size := high - low
		var volume := size.x * size.y * size.z
		if volume < best_volume:
			best_volume = volume
			best = surface
	return best


# Original (off) and lit copies of a light surface, made once.
func _light_materials(mesh_instance: MeshInstance3D, surface: int) -> Array:
	var key := "%d:%d" % [mesh_instance.get_instance_id(), surface]
	if _light_material_cache.has(key):
		return _light_material_cache[key]
	var material := mesh_instance.get_active_material(surface)
	var pair: Array = []
	# The model's materials are ORM materials, which are not StandardMaterial3D.
	if material is BaseMaterial3D:
		var off := material.duplicate() as BaseMaterial3D
		off.emission_enabled = false
		var lit := material.duplicate() as BaseMaterial3D
		lit.emission_enabled = true
		lit.emission = Color(1.0, 0.78, 0.28)
		lit.emission_energy_multiplier = 4.0
		pair = [off, lit]
	_light_material_cache[key] = pair
	return pair


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
	_glass_body = get_parent().get_node_or_null("GlassBody") as StaticBody3D
	if _glass_body != null:
		_glass_body_closed = _glass_body.transform
		_glass_hinge_root_closed = (get_parent() as Node3D).global_transform.affine_inverse() * _glass_hinge.global_transform
	for wanted in ["doorglass", "doorhandle", "doortoppanel", "Glass_Shards"]:
		# The hidden shard set travels with the leaf, so a pane broken while the
		# door is open crumbles where the glass stands, not in the closed pose.
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
	var eased := _open_amount * _open_amount * (3.0 - 2.0 * _open_amount)
	for i in _door_parts.size():
		var part := _door_parts[i]
		if not is_instance_valid(part):
			continue
		var closed := _closed_transforms[i]
		if mode == DoorMode.SLIDING_ELEVATOR:
			var direction := -1.0 if _left_slide_parts.has(part) else 1.0
			var t := closed
			t.origin.x += direction * slide_distance * eased
			part.transform = t
		elif mode == DoorMode.GLASS_SWING:
			pass
		else:
			var side := _swing_side
			if side == 0.0:
				side = signf(one_way_allowed_side) if mode == DoorMode.SWING_ONE_WAY else _player_side(local_player)
			var angle := deg_to_rad(open_angle_degrees * side * eased)
			var t := closed
			t.basis = closed.basis.rotated(Vector3.UP, angle)
			part.transform = t
