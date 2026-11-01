extends Node
## Bootstrap-owned visual mode. Injected actors/world, no gameplay mutations.
const SUBJECT := preload("res://game/bootstrap/app/occlusion_subject.gd")
const WALLS := preload("res://game/bootstrap/app/occlusion_wall_materials.gd")
const QUERY_LAYER := preload("res://game/bootstrap/app/occlusion_query_layer.gd")
const OUTLINES := preload("res://game/bootstrap/app/occlusion_outlines.gd")
const HERO_COLOR := Color(0.2, 0.85, 1.0, 0.9)
const HOLE_RADIUS := 2.0
const CHECK_INTERVAL := 0.1
const SUBJECTS_PER_TICK := 8
var mode := 0
var runtime_enabled := true
var player: Node3D
var camera: Camera3D
var world: Node3D
var subjects: Array[RefCounted] = []
var walls := WALLS.new()
var query_layer := QUERY_LAYER.new()
var outlines := OUTLINES.new()
var checks_last_tick := 0
var rays_last_tick := 0
var _subject_cursor := 0
var _check_credit := 0.0
var rebuild_count := 0
var _dirty := true
var _elapsed := 0.0
var _hero_blocked := false
var _hero_fog_blocked := false
var _subjects_by_id: Dictionary = {}
var _added_roots: Dictionary = {}
var _removed_roots: Dictionary = {}


func setup(actor: Node3D, view: Camera3D, scene: Node3D) -> void:
	player = actor
	camera = view
	world = scene
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_node_added)
	get_tree().node_removed.connect(_node_removed)


func set_mode(value: int) -> void:
	var selected := clampi(value, 0, 1)
	if selected == mode:
		return
	_clear()
	mode = selected
	_dirty = true


func set_runtime_enabled(value: bool) -> void:
	runtime_enabled = value
	_clear()
	_dirty = true


func _node_added(node: Node) -> void:
	if node.has_meta("occlusion_copy") or not node is Node3D:
		return
	# Classification and imported children can be installed in _ready.
	call_deferred("_check_added_root", weakref(node))


func _node_removed(node: Node) -> void:
	if node.has_meta("occlusion_copy"):
		return
	var id := node.get_instance_id()
	if _subjects_by_id.has(id) or node.is_in_group("camera_occluder") or walls.records.has(id) or walls.queued.has(id) or query_layer.records.has(id):
		_removed_roots[id] = weakref(node)
	_added_roots.erase(id)


func _is_classified(node: Node) -> bool:
	return node == player or node.is_in_group("camera_occluder")


func _check_added_root(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if node is CollisionObject3D and world.is_ancestor_of(node):
		var ancestor := node.get_parent()
		while ancestor != null and ancestor != world:
			if ancestor is Node3D and ancestor.is_in_group("camera_occluder"):
				query_layer.add_root(ancestor)
				break
			ancestor = ancestor.get_parent()
	if node != null and node.is_inside_tree() and world.is_ancestor_of(node) and _is_classified(node):
		_added_roots[node.get_instance_id()] = weakref(node)


func _physics_process(delta: float) -> void:
	checks_last_tick = 0
	rays_last_tick = 0
	if not runtime_enabled or not is_instance_valid(player) or not is_instance_valid(camera):
		return
	if _dirty:
		_rebuild()
	else:
		_apply_pending_roots()
	outlines.tick(delta, self)
	if mode == 0:
		_check_credit = minf(_check_credit + delta * subjects.size() / CHECK_INTERVAL, SUBJECTS_PER_TICK)
		var count := mini(int(_check_credit), SUBJECTS_PER_TICK)
		_check_credit -= count
		_check_subjects(count)
	else:
		_elapsed += delta
		if _elapsed >= CHECK_INTERVAL:
			_elapsed = 0.0
			_check_subjects()


func _process(_delta: float) -> void:
	if runtime_enabled and mode == 1 and is_instance_valid(player) and is_instance_valid(camera):
		_update_hole()


## Installs every queued wall material now, so the first gameplay frames do not pay for them one dozen at a time.
func flush_wall_queue(tree: SceneTree, batch: int = 64) -> void:
	if not runtime_enabled or mode != 1:
		return
	if _dirty:
		_rebuild()
	else:
		_apply_pending_roots()
	while not walls.pending.is_empty():
		walls.install_pending(batch)
		await tree.process_frame


func _rebuild() -> void:
	rebuild_count += 1
	_clear()
	_collect(world)
	_dirty = false
	_elapsed = CHECK_INTERVAL


func _apply_pending_roots() -> void:
	for id in _removed_roots:
		if _subjects_by_id.has(id):
			var subject: RefCounted = _subjects_by_id[id]
			subject.clear()
			subjects.erase(subject)
			_subjects_by_id.erase(id)
		var removed: Node = _removed_roots[id].get_ref()
		if removed != null:
			walls.remove_root(removed)
			query_layer.remove_root(removed)
	_removed_roots.clear()
	for reference: WeakRef in _added_roots.values():
		var node := reference.get_ref() as Node
		if node != null and node.is_inside_tree() and world.is_ancestor_of(node):
			_collect(node)
	_added_roots.clear()


func _collect(node: Node) -> void:
	if node.has_meta("occlusion_copy"):
		return
	if node is Node3D:
		if node.is_in_group("camera_occluder"):
			query_layer.add_root(node)
		if mode == 1 and node.is_in_group("camera_occluder"):
			walls.add_root(node)
		# Only the hero is highlighted in both modes; enemies get no silhouette.
		if node == player and not _subjects_by_id.has(node.get_instance_id()):
			_add_subject(node, HERO_COLOR)
	for child in node.get_children():
		_collect(child)


func _add_subject(node: Node3D, tint: Color) -> void:
	var subject := SUBJECT.new(node, tint, mode == 1 and node == player)
	_subjects_by_id[node.get_instance_id()] = subject
	subjects.append(subject)


func _check_subjects(limit: int = SUBJECTS_PER_TICK) -> void:
	if mode == 1:
		_hero_blocked = _blocked(player)
		var subject: RefCounted = _subjects_by_id.get(player.get_instance_id())
		if subject != null:
			subject.set_revealed(player.is_visible_in_tree() and _hero_blocked, _hero_fog_blocked)
		return
	for index in mini(limit, subjects.size()):
		_subject_cursor %= subjects.size()
		var subject: RefCounted = subjects[_subject_cursor]
		_subject_cursor += 1
		checks_last_tick += 1
		var node := subject.target.get_ref() as Node3D
		var live := node != null and node.is_visible_in_tree()
		if live and node.has_method("is_dead"):
			live = not bool(node.call("is_dead"))
		var blocked := live and _blocked(node)
		subject.set_revealed(blocked, node == player and _hero_fog_blocked)


func _blocked(node: Node3D) -> bool:
	if node == player:
		_hero_fog_blocked = false
	if camera.is_position_behind(node.global_position) or camera.global_position.distance_to(node.global_position) > 45.0:
		return false
	var screen := camera.unproject_position(node.global_position)
	if not get_viewport().get_visible_rect().grow(100.0).has_point(screen):
		return false
	for height in [0.2, 0.8, 1.4]:
		if _ray_blocked(node.global_position + Vector3.UP * height, node):
			return true
	return false


func _ray_blocked(point: Vector3, target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, point, QUERY_LAYER.MASK)
	if target is CollisionObject3D:
		query.exclude = [target.get_rid()]
	rays_last_tick += 1
	# Only the hero shows through darkness; enemies and items stay hidden in the fog.
	if target == player:
		for zone in get_tree().get_nodes_in_group("darkness_zone"):
			if zone.has_method("blocks_view") and zone.call("blocks_view", camera.global_position, point):
				_hero_fog_blocked = true
				return true
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var ancestor := hit.collider as Node
	while ancestor != null and ancestor != world:
		if ancestor.is_in_group("camera_occluder") and (ancestor as Node3D).is_visible_in_tree():
			return true
		ancestor = ancestor.get_parent()
	return false


func _update_hole() -> void:
	var point := player.global_position + Vector3.UP * 0.6
	var center := camera.unproject_position(point)
	var side := camera.unproject_position(point + camera.global_basis.x * HOLE_RADIUS)
	var size := get_viewport().get_visible_rect().size
	if size.x < 1.0 or size.y < 1.0 or not center.is_finite() or camera.is_position_behind(point):
		_set_hole(Vector2(-10, -10), Vector2.ONE, 0.0, 0.0)
		return
	var depth := -(camera.global_transform.affine_inverse() * point).z
	_set_hole(center / size, size, center.distance_to(side) if _hero_blocked else 0.0, depth)


## The lens accents the blocking wall, without exposing the room behind it.
func _set_hole(center: Vector2, size: Vector2, radius: float, depth: float) -> void:
	walls.update_hole(center, size, radius, depth)
	for subject in subjects:
		subject.set_lens(center, size, radius, depth)
	for zone in get_tree().get_nodes_in_group("darkness_zone"):
		if zone.has_method("set_view_hole"):
			zone.call("set_view_hole", center, size, radius, depth)


func _clear() -> void:
	for subject in subjects:
		subject.clear()
	subjects.clear()
	_subjects_by_id.clear()
	_added_roots.clear()
	_removed_roots.clear()
	walls.clear()
	query_layer.clear()
	outlines.clear()
	if is_inside_tree():
		_set_hole(Vector2(-10, -10), Vector2.ONE, 0.0, 0.0)
	_subject_cursor = 0
	_check_credit = 0.0
	_hero_blocked = false
	_hero_fog_blocked = false


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.disconnect(_node_added)
		get_tree().node_removed.disconnect(_node_removed)
	_clear()
